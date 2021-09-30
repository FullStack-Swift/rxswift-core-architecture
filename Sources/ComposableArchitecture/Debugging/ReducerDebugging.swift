import CasePaths
import Dispatch

public enum ActionFormat {
  case labelsOnly
  case prettyPrint
}

extension Reducer {
    
    /// debug
    /// - Parameters:
    ///   - prefix: prefix description
    ///   - actionFormat: actionFormat description
    ///   - toDebugEnvironment: toDebugEnvironment description
    /// - Returns: Reducer
  public func debug(
    _ prefix: String = "",
    actionFormat: ActionFormat = .prettyPrint,
    environment toDebugEnvironment: @escaping (Environment) -> DebugEnvironment = { _ in
      DebugEnvironment()
    }
  ) -> Reducer {
    self.debug(
      prefix,
      state: { $0 },
      action: .self,
      actionFormat: actionFormat,
      environment: toDebugEnvironment
    )
  }
    
    /// debugActions
    /// - Parameters:
    ///   - prefix: prefix description
    ///   - actionFormat: actionFormat description
    ///   - toDebugEnvironment: toDebugEnvironment description
    /// - Returns: Reducer
  public func debugActions(
    _ prefix: String = "",
    actionFormat: ActionFormat = .prettyPrint,
    environment toDebugEnvironment: @escaping (Environment) -> DebugEnvironment = { _ in
      DebugEnvironment()
    }
  ) -> Reducer {
    self.debug(
      prefix,
      state: { _ in () },
      action: .self,
      actionFormat: actionFormat,
      environment: toDebugEnvironment
    )
  }
    
    /// debug
    /// - Returns: Reducer
  public func debug<LocalState, LocalAction>(
    _ prefix: String = "",
    state toLocalState: @escaping (State) -> LocalState,
    action toLocalAction: CasePath<Action, LocalAction>,
    actionFormat: ActionFormat = .prettyPrint,
    environment toDebugEnvironment: @escaping (Environment) -> DebugEnvironment = { _ in
      DebugEnvironment()
    }
  ) -> Reducer {
    #if DEBUG
      return self
    #else
      return self
    #endif
  }
}

/// An environment for debug-printing reducers.
public struct DebugEnvironment {
  public var printer: (String) -> Void
  public var queue: DispatchQueue

  public init(
    printer: @escaping (String) -> Void = { print($0) },
    queue: DispatchQueue
  ) {
    self.printer = printer
    self.queue = queue
  }

  public init(
    printer: @escaping (String) -> Void = { print($0) }
  ) {
    self.init(printer: printer, queue: _queue)
  }
}

private let _queue = DispatchQueue(
  label: "ComposableArchitecture.DebugEnvironment",
  qos: .background
)
