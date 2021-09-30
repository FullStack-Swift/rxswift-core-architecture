import CasePaths
import RxSwift

public struct Reducer<State, Action, Environment> {
    
  private let reducer: (inout State, Action, Environment) -> Effect<Action>

    /// Reducer
    /// - Parameter reducer: reducer
  public init(_ reducer: @escaping (inout State, Action, Environment) -> Effect<Action>) {
    self.reducer = reducer
  }
    
    /// Reducer
  public static var empty: Reducer {
    Self { _, _, _ in .none }
  }
    
    /// Reducer
    /// - Parameter reducers: reducers
    /// - Returns: Reducer
  public static func combine(_ reducers: Reducer...) -> Reducer {
    .combine(reducers)
  }
    
    /// Reducer
    /// - Parameter reducers: reducers
    /// - Returns: Reducer
  public static func combine(_ reducers: [Reducer]) -> Reducer {
    Self { value, action, environment in
      .merge(reducers.map { $0.reducer(&value, action, environment) })
    }
  }
    
    /// Reducer
    /// - Parameter other: other reducer
    /// - Returns: Reducer
  public func combined(with other: Reducer) -> Reducer {
    .combine(self, other)
  }
    
    /// pullback
    /// - Returns: Reducer
  public func pullback<GlobalState, GlobalAction, GlobalEnvironment>(
    state toLocalState: WritableKeyPath<GlobalState, State>,
    action toLocalAction: CasePath<GlobalAction, Action>,
    environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment
  ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
    .init { globalState, globalAction, globalEnvironment in
      guard let localAction = toLocalAction.extract(from: globalAction) else { return .none }
      return self.reducer(
        &globalState[keyPath: toLocalState],
        localAction,
        toLocalEnvironment(globalEnvironment)
      )
      .map(toLocalAction.embed)
    }
  }
    
    /// optional
    /// - Returns: Reducer
  public func optional(_ file: StaticString = #file, _ line: UInt = #line) -> Reducer<
    State?, Action, Environment
  > {
    .init { state, action, environment in
      guard state != nil else {
        return .none
      }
      return self.reducer(&state!, action, environment)
    }
  }
    
    /// forEach
    /// - Returns: Reducer
  public func forEach<GlobalState, GlobalAction, GlobalEnvironment>(
    state toLocalState: WritableKeyPath<GlobalState, [State]>,
    action toLocalAction: CasePath<GlobalAction, (Int, Action)>,
    environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment,
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
    .init { globalState, globalAction, globalEnvironment in
      guard let (index, localAction) = toLocalAction.extract(from: globalAction) else {
        return .none
      }
      return self.reducer(
        &globalState[keyPath: toLocalState][index],
        localAction,
        toLocalEnvironment(globalEnvironment)
      )
      .map { toLocalAction.embed((index, $0)) }
    }
  }
    
    /// forEach
    /// - Returns: Effect
  public func forEach<GlobalState, GlobalAction, GlobalEnvironment, Key>(
    state toLocalState: WritableKeyPath<GlobalState, [Key: State]>,
    action toLocalAction: CasePath<GlobalAction, (Key, Action)>,
    environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment,
    _ file: StaticString = #file,
    _ line: UInt = #line
  ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
    .init { globalState, globalAction, globalEnvironment in
      guard let (key, localAction) = toLocalAction.extract(from: globalAction) else { return .none }
      return self.reducer(
        &globalState[keyPath: toLocalState][key]!,
        localAction,
        toLocalEnvironment(globalEnvironment)
      )
      .map { toLocalAction.embed((key, $0)) }
    }
  }
    
    /// Effect
    /// - Parameters:
    ///   - state: state
    ///   - action: action
    ///   - environment: environment
    /// - Returns: Effect
  public func run(
    _ state: inout State,
    _ action: Action,
    _ environment: Environment
  ) -> Effect<Action> {
    self.reducer(&state, action, environment)
  }
    
    /// Effect
    /// - Parameters:
    ///   - state: state
    ///   - action: action
    ///   - environment: environment
    /// - Returns: Effect
  public func callAsFunction(
    _ state: inout State,
    _ action: Action,
    _ environment: Environment
  ) -> Effect<Action> {
    self.reducer(&state, action, environment)
  }
}
