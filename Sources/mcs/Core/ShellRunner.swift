import Foundation

/// Result of running a shell command.
struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        exitCode == 0
    }
}

/// Protocol for shell command execution, enabling test mocks to avoid real process spawning.
protocol ShellRunning: Sendable {
    /// The environment providing paths and configuration.
    var environment: Environment { get }

    /// Check if a command exists on PATH.
    func commandExists(_ command: String) -> Bool

    /// Run an executable with arguments, capturing stdout and stderr.
    @discardableResult
    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult

    /// Run a shell command string via /bin/bash -c.
    @discardableResult
    func shell(
        _ command: String,
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult
}

// MARK: - Default Parameter Values

extension ShellRunning {
    @discardableResult
    func run(
        _ executable: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        additionalEnvironment: [String: String] = [:],
        interactive: Bool = false
    ) -> ShellResult {
        run(
            executable, arguments: arguments, workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment, interactive: interactive
        )
    }

    @discardableResult
    func shell(
        _ command: String,
        workingDirectory: String? = nil,
        additionalEnvironment: [String: String] = [:],
        interactive: Bool = false
    ) -> ShellResult {
        shell(
            command, workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment, interactive: interactive
        )
    }
}

/// Runs shell commands and captures output.
struct ShellRunner: ShellRunning {
    let environment: Environment

    /// Check if a command exists on PATH.
    func commandExists(_ command: String) -> Bool {
        let result = run(Constants.CLI.which, arguments: [command])
        return result.succeeded
    }

    /// Run an executable with arguments, capturing stdout and stderr.
    ///
    /// - Parameter interactive: When `true`, uses `forkpty()` to allocate a
    ///   real pseudo-terminal so commands like `sudo` can prompt for passwords
    ///   securely. Output goes directly to the terminal (not captured); the
    ///   returned `ShellResult` will have empty `stdout` and `stderr`.
    ///   Defaults to `false` (stdin `/dev/null`, stdout/stderr piped).
    @discardableResult
    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = environment.pathWithBrew
        for (key, value) in additionalEnvironment {
            env[key] = value
        }

        if interactive {
            return runInteractive(
                executable: executable, arguments: arguments,
                environment: env, workingDirectory: workingDirectory
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = env

        if let cwd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Prevent subprocesses from blocking on stdin.
        // Without this, interactive commands (e.g. npx prompts) inherit the
        // parent's TTY and can deadlock: the child waits for stdin while
        // readDataToEndOfFile blocks waiting for stdout EOF.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }

        // Read pipe data BEFORE waitUntilExit to avoid deadlock.
        // If a child process fills the pipe buffer (~64KB), waitUntilExit blocks
        // because the child can't write more, creating a circular wait.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .newlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .newlines) ?? ""

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    /// Run a shell command string via /bin/bash -c.
    @discardableResult
    func shell(
        _ command: String,
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult {
        run(
            Constants.CLI.bash,
            arguments: ["-c", command],
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
            interactive: interactive
        )
    }

    /// Run a command with a real pseudo-terminal using `forkpty()`.
    ///
    /// `Foundation.Process` never allocates a PTY, so commands like `sudo`
    /// that require `isatty() == true` fail with "unable to read password".
    /// This method uses `forkpty()` to create a real PTY pair and then
    /// bridges I/O between the parent terminal and the child's PTY so that
    /// `sudo` can properly disable echo and read passwords securely.
    /// The returned `ShellResult` has empty `stdout` and `stderr` since
    /// output goes directly to the terminal.
    private func runInteractive(
        executable: String,
        arguments: [String],
        environment env: [String: String],
        workingDirectory: String?
    ) -> ShellResult {
        // Prepare environment and argv as C strings for execve().
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { key, value in
            strdup("\(key)=\(value)")
        } + [nil]
        defer { envp.compactMap(\.self).forEach { free($0) } }

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.compactMap(\.self).forEach { free($0) } }

        // Save the terminal's current attributes so we can restore them after.
        var originalTermios = termios()
        let hasTerminal = tcgetattr(STDIN_FILENO, &originalTermios) == 0

        // forkpty() creates a PTY pair and forks.
        // Parent gets the PTY fd; child gets stdin/stdout/stderr on the other end.
        var ptyFD: Int32 = -1
        let pid = forkpty(&ptyFD, nil, nil, nil)

        if pid == -1 {
            return ShellResult(exitCode: 1, stdout: "", stderr: "forkpty failed: \(String(cString: strerror(errno)))")
        }

        if pid == 0 {
            // ── Child process ──
            if let cwd = workingDirectory {
                if chdir(cwd) != 0 {
                    let msg = "chdir failed: \(String(cString: strerror(errno)))\n"
                    msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                    _exit(126)
                }
            }
            execve(executable, argv, envp)
            let msg = "execve failed: \(String(cString: strerror(errno)))\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            _exit(127)
        }

        // ── Parent process ──
        // Put terminal in raw-ish mode so keystrokes (including Enter for sudo)
        // are forwarded immediately without local echo interference, while still
        // allowing terminal-generated signals like Ctrl-C / Ctrl-Z.
        if hasTerminal {
            var raw = originalTermios
            cfmakeraw(&raw)
            raw.c_lflag |= tcflag_t(ISIG)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }

        // Ensure terminal is restored even if we exit early or the process is interrupted.
        defer {
            if hasTerminal {
                if tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios) != 0 {
                    tcsetattr(STDIN_FILENO, TCSADRAIN, &originalTermios)
                }
            }
            close(ptyFD)
        }

        // Bridge I/O between the real terminal and the PTY.
        // Uses select() to multiplex stdin → PTY and PTY → stdout.
        let stdinFD = STDIN_FILENO
        let stdoutFD = STDOUT_FILENO
        var buf = [UInt8](repeating: 0, count: 4096)
        var stdinOpen = true

        bridgeLoop: while true {
            var readSet = fd_set()
            fdZero(&readSet)
            if stdinOpen { fdSet(stdinFD, set: &readSet) }
            fdSet(ptyFD, set: &readSet)

            let maxFD = max(stdinOpen ? stdinFD : 0, ptyFD) + 1
            let ready = select(maxFD, &readSet, nil, nil, nil)
            if ready < 0 {
                if errno == EINTR { continue } // Retry on signal interruption
                break
            }
            if ready == 0 { continue }

            // Terminal → PTY (user typing, including password input)
            if stdinOpen, fdIsSet(stdinFD, set: &readSet) {
                let n = read(stdinFD, &buf, buf.count)
                if n <= 0 {
                    stdinOpen = false // stdin EOF — stop monitoring
                } else {
                    writeAll(fd: ptyFD, buf: &buf, count: n)
                }
            }

            // PTY → Terminal (command output, prompts, progress bars)
            if fdIsSet(ptyFD, set: &readSet) {
                let n = read(ptyFD, &buf, buf.count)
                if n <= 0 { break bridgeLoop } // Child closed the PTY
                writeAll(fd: stdoutFD, buf: &buf, count: n)
            }
        }

        // Wait for the child and extract exit status.
        // Equivalent to WIFEXITED/WEXITSTATUS — Swift doesn't expose wait status macros.
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            if errno != EINTR { break }
        }
        let exitCode: Int32 = if status & 0x7F == 0 {
            (status >> 8) & 0xFF
        } else {
            // Killed by signal — report as 128 + signal (shell convention).
            128 + (status & 0x7F)
        }

        return ShellResult(exitCode: exitCode, stdout: "", stderr: "")
    }

    /// Write all bytes to a file descriptor, retrying on partial writes and EINTR.
    private func writeAll(fd: Int32, buf: inout [UInt8], count: Int) {
        buf.withUnsafeBufferPointer { ptr in
            var offset = 0
            while offset < count {
                let n = write(fd, ptr.baseAddress! + offset, count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    break // EIO/EPIPE — fd closed
                }
                offset += n
            }
        }
    }

    // MARK: - fd_set Helpers

    // Swift doesn't expose FD_ZERO / FD_SET / FD_ISSET macros.

    private func fdZero(_ set: inout fd_set) {
        withUnsafeMutablePointer(to: &set) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr)
            memset(rawPtr, 0, MemoryLayout<fd_set>.size)
        }
    }

    private func fdSet(_ fd: Int32, set: inout fd_set) {
        let intOffset = Int(fd) / (MemoryLayout<Int32>.size * 8)
        let bitOffset = Int(fd) % (MemoryLayout<Int32>.size * 8)
        withUnsafeMutablePointer(to: &set) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Int32.self)
            rawPtr[intOffset] |= Int32(1 << bitOffset)
        }
    }

    private func fdIsSet(_ fd: Int32, set: inout fd_set) -> Bool {
        let intOffset = Int(fd) / (MemoryLayout<Int32>.size * 8)
        let bitOffset = Int(fd) % (MemoryLayout<Int32>.size * 8)
        return withUnsafeMutablePointer(to: &set) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Int32.self)
            return rawPtr[intOffset] & Int32(1 << bitOffset) != 0
        }
    }
}
