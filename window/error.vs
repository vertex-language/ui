package window

/// Every way an operation in this package fails.
public enum WindowError: Error {
    /// There is no window system here to ask.
    case unsupported(string)
    /// There is a window system but no session to show a window in, or this
    /// is not the thread it has to be asked from.
    case noDisplay(string)
    /// An argument the window system cannot use.
    case invalidArgument(string)
    /// Anything else, with what was being attempted.
    case systemError(code: int32, context: string)

    /// A sentence naming what failed.
    public var Message: string {
        switch self {
        case .unsupported(let what): return "unsupported: \(what)"
        case .noDisplay(let what): return "no display: \(what)"
        case .invalidArgument(let what): return "invalid argument: \(what)"
        case .systemError(let code, let what): return "system error \(code): \(what)"
        }
    }
}

// errorFor is the error a negative window.cpp result stands for.
func errorFor(_ code: int32, _ context: string) -> WindowError {
    switch code {
    case -1: return .unsupported(context)
    case -2: return .noDisplay(context)
    case -3: return .invalidArgument(context)
    default: return .systemError(code: code, context: context)
    }
}
