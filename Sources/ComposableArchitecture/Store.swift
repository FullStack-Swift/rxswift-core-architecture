import Foundation
import RxRelay
import RxSwift

/// A store represents the runtime that powers the application. It is the object that you will pass
/// around to views that need to interact with the application.
///
/// You will typically construct a single one of these at the root of your application:
///
/// ```swift
/// @main
/// struct MyApp: App {
///   var body: some Scene {
///     WindowGroup {
///       RootView(
///         store: Store(
///           initialState: AppReducer.State(),
///           reducer: AppReducer()
///         )
///       )
///     }
///   }
/// }
/// ```
///
/// …and then use the ``scope(state:action:)`` method to derive more focused stores that can be
/// passed to subviews.
///
/// ### Scoping
///
/// The most important operation defined on ``Store`` is the ``scope(state:action:)`` method, which
/// allows you to transform a store into one that deals with child state and actions. This is
/// necessary for passing stores to subviews that only care about a small portion of the entire
/// application's domain.
///
/// For example, if an application has a tab view at its root with tabs for activity, search, and
/// profile, then we can model the domain like this:
///
/// ```swift
/// struct State {
///   var activity: Activity.State
///   var profile: Profile.State
///   var search: Search.State
/// }
///
/// enum Action {
///   case activity(Activity.Action)
///   case profile(Profile.Action)
///   case search(Search.Action)
/// }
/// ```
///
/// We can construct a view for each of these domains by applying ``scope(state:action:)`` to a
/// store that holds onto the full app domain in order to transform it into a store for each
/// sub-domain:
///
/// ```swift
/// struct AppView: View {
///   let store: StoreOf<AppReducer>
///
///   var body: some View {
///     TabView {
///       ActivityView(store: self.store.scope(state: \.activity, action: App.Action.activity))
///         .tabItem { Text("Activity") }
///
///       SearchView(store: self.store.scope(state: \.search, action: App.Action.search))
///         .tabItem { Text("Search") }
///
///       ProfileView(store: self.store.scope(state: \.profile, action: App.Action.profile))
///         .tabItem { Text("Profile") }
///     }
///   }
/// }
/// ```
///
/// ### Thread safety
///
/// The `Store` class is not thread-safe, and so all interactions with an instance of ``Store``
/// (including all of its scopes and derived ``ViewStore``s) must be done on the same thread the
/// store was created on. Further, if the store is powering a SwiftUI or UIKit view, as is
/// customary, then all interactions must be done on the _main_ thread.
///
/// The reason stores are not thread-safe is due to the fact that when an action is sent to a store,
/// a reducer is run on the current state, and this process cannot be done from multiple threads.
/// It is possible to make this process thread-safe by introducing locks or queues, but this
/// introduces new complications:
///
///   * If done simply with `DispatchQueue.main.async` you will incur a thread hop even when you are
///     already on the main thread. This can lead to unexpected behavior in UIKit and SwiftUI, where
///     sometimes you are required to do work synchronously, such as in animation blocks.
///
///   * It is possible to create a scheduler that performs its work immediately when on the main
///     thread and otherwise uses `DispatchQueue.main.async` (_e.g._, see Combine Schedulers'
///     [UIScheduler][uischeduler]).
///
/// This introduces a lot more complexity, and should probably not be adopted without having a very
/// good reason.
///
/// This is why we require all actions be sent from the same thread. This requirement is in the same
/// spirit of how `URLSession` and other Apple APIs are designed. Those APIs tend to deliver their
/// outputs on whatever thread is most convenient for them, and then it is your responsibility to
/// dispatch back to the main queue if that's what you need. The Composable Architecture makes you
/// responsible for making sure to send actions on the main thread. If you are using an effect that
/// may deliver its output on a non-main thread, you must explicitly perform `.receive(on:)` in
/// order to force it back on the main thread.
///
/// This approach makes the fewest number of assumptions about how effects are created and
/// transformed, and prevents unnecessary thread hops and re-dispatching. It also provides some
/// testing benefits. If your effects are not responsible for their own scheduling, then in tests
/// all of the effects would run synchronously and immediately. You would not be able to test how
/// multiple in-flight effects interleave with each other and affect the state of your application.
/// However, by leaving scheduling out of the ``Store`` we get to test these aspects of our effects
/// if we so desire, or we can ignore if we prefer. We have that flexibility.
///
/// [uischeduler]: https://github.com/pointfreeco/combine-schedulers/blob/main/Sources/CombineSchedulers/UIScheduler.swift
///
/// #### Thread safety checks
///
/// The store performs some basic thread safety checks in order to help catch mistakes. Stores
/// constructed via the initializer ``init(initialState:reducer:prepareDependencies:)`` are assumed
/// to run only on the main thread, and so a check is executed immediately to make sure that is the
/// case. Further, all actions sent to the store and all scopes (see ``scope(state:action:)``) of
/// the store are also checked to make sure that work is performed on the main thread.

public final class Store<State, Action> {
  private var bufferedActions: [Action] = []
  @_spi(Internals) public var effectCancellables: [UUID: Disposable] = [:]
  private var isSending = false
  var parentCancellable: Disposable?
//  private let reducer: (inout State, Action) -> Effect<Action>
//  var state: BehaviorRelay<State>
//#if DEBUG
//  private let mainThreadChecksEnabled: Bool
//#endif
#if swift(>=5.7)
  private let reducer: any ReducerProtocol<State, Action>
#else
  private let reducer: (inout State, Action) -> EffectTask<Action>
  fileprivate var scope: AnyStoreScope?
#endif
  @_spi(Internals) public var state: BehaviorRelay<State>
#if DEBUG
  private let mainThreadChecksEnabled: Bool
#endif
  
  /// Initializes a store from an initial state and a reducer.
  ///
  /// - Parameters:
  ///   - initialState: The state to start the application in.
  ///   - reducer: The reducer that powers the business logic of the application.
  ///   - prepareDependencies: A closure that can be used to override dependencies that will be accessed
  ///     by the reducer.
  public convenience init<R: ReducerProtocol>(
    initialState: @autoclosure () -> R.State,
    reducer: R
  ) where R.State == State, R.Action == Action {
    self.init(
      initialState: initialState(),
      reducer: reducer,
      mainThreadChecksEnabled: true
    )
  }

    /// Scopes the store to one that exposes local state and actions.
    ///
    /// This can be useful for deriving new stores to hand to child views in an application. For
    /// example:
    ///
    /// ```swift
    /// // Application state made from local states.
    /// struct AppState { var login: LoginState, ... }
    /// struct AppAction { case login(LoginAction), ... }
    ///
    /// // A store that runs the entire application.
    /// let store = Store(
    ///   initialState: AppState(),
    ///   reducer: appReducer,
    ///   environment: AppEnvironment()
    /// )
    ///
    /// // Construct a login view by scoping the store to one that works with only login domain.
    /// LoginView(
    ///   store: store.scope(
    ///     state: \.login,
    ///     action: AppAction.login
    ///   )
    /// )
    /// ```
    ///
    /// Scoping in this fashion allows you to better modularize your application. In this case,
    /// `LoginView` could be extracted to a module that has no access to `AppState` or `AppAction`.
    ///
    /// Scoping also gives a view the opportunity to focus on just the state and actions it cares
    /// about, even if its feature domain is larger.
    ///
    /// For example, the above login domain could model a two screen login flow: a login form followed
    /// by a two-factor authentication screen. The second screen's domain might be nested in the
    /// first:
    ///
    /// ```swift
    /// struct LoginState: Equatable {
    ///   var email = ""
    ///   var password = ""
    ///   var twoFactorAuth: TwoFactorAuthState?
    /// }
    ///
    /// enum LoginAction: Equatable {
    ///   case emailChanged(String)
    ///   case loginButtonTapped
    ///   case loginResponse(Result<TwoFactorAuthState, LoginError>)
    ///   case passwordChanged(String)
    ///   case twoFactorAuth(TwoFactorAuthAction)
    /// }
    /// ```
    ///
    /// The login view holds onto a store of this domain:
    /// ```swift
    /// struct LoginView: View {
    ///   let store: Store<LoginState, LoginAction>
    ///
    ///   var body: some View { ... }
    /// }
    /// ```
    ///
    /// If its body were to use a view store of the same domain, this would introduce a number of
    /// problems:
    ///
    /// * The login view would be able to read from `twoFactorAuth` state. This state is only intended
    ///   to be read from the two-factor auth screen.
    ///
    /// * Even worse, changes to `twoFactorAuth` state would now cause SwiftUI to recompute
    ///   `LoginView`'s body unnecessarily.
    ///
    /// * The login view would be able to send `twoFactorAuth` actions. These actions are only
    ///   intended to be sent from the two-factor auth screen (and reducer).
    ///
    /// * The login view would be able to send non user-facing login actions, like `loginResponse`.
    ///   These actions are only intended to be used in the login reducer to feed the results of
    ///   effects back into the store.
    ///
    /// To avoid these issues, one can introduce a view-specific domain that slices off the subset of
    /// state and actions that a view cares about:
    ///
    /// ```swift
    /// extension LoginView {
    ///   struct State: Equatable {
    ///     var email: String
    ///     var password: String
    ///   }
    ///
    ///   enum Action: Equatable {
    ///     case emailChanged(String)
    ///     case loginButtonTapped
    ///     case passwordChanged(String)
    ///   }
    /// }
    /// ```
    ///
    /// One can also introduce a couple helpers that transform feature state into view state and
    /// transform view actions into feature actions.
    ///
    /// ```swift
    /// extension LoginState {
    ///   var view: LoginView.State {
    ///     .init(email: self.email, password: self.password)
    ///   }
    /// }
    ///
    /// extension LoginView.Action {
    ///   var feature: LoginAction {
    ///     switch self {
    ///     case let .emailChanged(email)
    ///       return .emailChanged(email)
    ///     case .loginButtonTapped:
    ///       return .loginButtonTapped
    ///     case let .passwordChanged(password)
    ///       return .passwordChanged(password)
    ///     }
    ///   }
    /// }
    /// ```
    ///
    /// With these helpers defined, `LoginView` can now scope its store's feature domain into its view
    /// domain:
    ///
    /// ```swift
    ///  var body: some View {
    ///    WithViewStore(
    ///      self.store.scope(state: \.view, action: \.feature)
    ///    ) { viewStore in
    ///      ...
    ///    }
    ///  }
    /// ```
    ///
    /// This view store is now incapable of reading any state but view state (and will not recompute
    /// when non-view state changes), and is incapable of sending any actions but view actions.
    ///
    /// - Parameters:
    ///   - toLocalState: A function that transforms `State` into `LocalState`.
    ///   - fromLocalAction: A function that transforms `LocalAction` into `Action`.
    /// - Returns: A new store with its domain (state and action) transformed.
    public func scope<LocalState, LocalAction>(
      state toLocalState: @escaping (State) -> LocalState,
      action fromLocalAction: @escaping (LocalAction) -> Action
    ) -> Store<LocalState, LocalAction> {
      fatalError()
//      self.threadCheck(status: .scope)
//      var isSending = false
//      let localStore = Store<LocalState, LocalAction>(
//        initialState: toLocalState(self.state.value),
//        reducer: .init { localState, localAction, _ in
//          isSending = true
//          defer { isSending = false }
//          self.send(fromLocalAction(localAction))
//          localState = toLocalState(self.state.value)
//          return .none
//        },
//        environment: ()
//      )
//      localStore.parentCancellable = self.state
//        .skip(1)
//        .subscribe({ [weak localStore] event in
//          switch event {
//          case .next(let newValue):
//            guard !isSending else { return }
//            localStore?.state.accept(toLocalState(newValue))
//          default:
//            break
//          }
//        })
//      return localStore
    }

    /// Scopes the store to one that exposes local state.
    ///
    /// - Parameter toLocalState: A function that transforms `State` into `LocalState`.
    /// - Returns: A new store with its domain (state and action) transformed.
    public func scope<LocalState>(
      state toLocalState: @escaping (State) -> LocalState
    ) -> Store<LocalState, Action> {
      self.scope(state: toLocalState, action: { $0 })
    }

    func send(_ action: Action, originatingFrom originatingAction: Action? = nil) {
      self.threadCheck(status: .send(action, originatingAction: originatingAction))

      self.bufferedActions.append(action)
      guard !self.isSending else { return }

      self.isSending = true
      var currentState = self.state.value
      defer {
        self.isSending = false
        self.state.accept(currentState)
      }

//      while !self.bufferedActions.isEmpty {
//        let action = self.bufferedActions.removeFirst()
//        let effect = self.reducer(&currentState, action)
//
//        var didComplete = false
//        let uuid = UUID()
//        let effectCancellable = effect.subscribe({ [weak self] event in
//          switch event {
//          case .next(let effectAction):
//            self?.send(effectAction, originatingFrom: action)
//          default:
//            self?.threadCheck(status: .effectCompletion(action))
//            didComplete = true
//            self?.effectCancellables[uuid] = nil
//          }
//        })
//        if !didComplete {
//          self.effectCancellables[uuid] = effectCancellable
//        }
//      }
    }

    /// Returns a "stateless" store by erasing state to `Void`.
    public var stateless: Store<Void, Action> {
      self.scope(state: { _ in () })
    }

    /// Returns an "actionless" store by erasing action to `Never`.
    public var actionless: Store<State, Never> {
      func absurd<A>(_ never: Never) -> A {}
      return self.scope(state: { $0 }, action: absurd)
    }

    private enum ThreadCheckStatus {
      case effectCompletion(Action)
      case `init`
      case scope
      case send(Action, originatingAction: Action?)
    }

    @inline(__always)
    private func threadCheck(status: ThreadCheckStatus) {

    }

  init<R: ReducerProtocol>(
    initialState: R.State,
    reducer: R,
    mainThreadChecksEnabled: Bool
  ) where R.State == State, R.Action == Action {
    self.state = BehaviorRelay(value: initialState)
#if swift(>=5.7)
    self.reducer = reducer
#else
    self.reducer = reducer.reduce
#endif
#if DEBUG
    self.mainThreadChecksEnabled = mainThreadChecksEnabled
#endif
    self.threadCheck(status: .`init`)
  }

  deinit {
    for effect in effectCancellables.values {
      effect.dispose()
    }
    parentCancellable?.dispose()
  }
}

/// A convenience type alias for referring to a store of a given reducer's domain.
///
/// Instead of specifying two generics:
///
/// ```swift
/// let store: Store<Feature.State, Feature.Action>
/// ```
///
/// You can specify a single generic:
///
/// ```swift
/// let store: StoreOf<Feature>
/// ```
public typealias StoreOf<R: ReducerProtocol> = Store<R.State, R.Action>

#if swift(>=5.7)
extension ReducerProtocol {
  fileprivate func rescope<ChildState, ChildAction>(
    _ store: Store<State, Action>,
    state toChildState: @escaping (State) -> ChildState,
    action fromChildAction: @escaping (ChildState, ChildAction) -> Action?
  ) -> Store<ChildState, ChildAction> {
    (self as? any AnyScopedReducer ?? ScopedReducer(rootStore: store))
      .rescope(store, state: toChildState, action: fromChildAction)
  }
}

private final class ScopedReducer<
  RootState, RootAction, ScopedState, ScopedAction
>: ReducerProtocol {
  let rootStore: Store<RootState, RootAction>
  let toScopedState: (RootState) -> ScopedState
  private let parentStores: [Any]
  let fromScopedAction: (ScopedState, ScopedAction) -> RootAction?
  private(set) var isSending = false

  @inlinable
  init(rootStore: Store<RootState, RootAction>)
  where RootState == ScopedState, RootAction == ScopedAction {
    self.rootStore = rootStore
    self.toScopedState = { $0 }
    self.parentStores = []
    self.fromScopedAction = { $1 }
  }

  @inlinable
  init(
    rootStore: Store<RootState, RootAction>,
    state toScopedState: @escaping (RootState) -> ScopedState,
    action fromScopedAction: @escaping (ScopedState, ScopedAction) -> RootAction?,
    parentStores: [Any]
  ) {
    self.rootStore = rootStore
    self.toScopedState = toScopedState
    self.fromScopedAction = fromScopedAction
    self.parentStores = parentStores
  }

  @inlinable
  func reduce(
    into state: inout ScopedState, action: ScopedAction
  ) -> EffectTask<ScopedAction> {
    self.isSending = true
    defer {
      state = self.toScopedState(self.rootStore.state.value)
      self.isSending = false
    }
    if let action = self.fromScopedAction(state, action) {
//      return EffectTask(value: action)
      return .none
    } else {
      return .none
    }
  }
}

protocol AnyScopedReducer {
  func rescope<ScopedState, ScopedAction, RescopedState, RescopedAction>(
    _ store: Store<ScopedState, ScopedAction>,
    state toRescopedState: @escaping (ScopedState) -> RescopedState,
    action fromRescopedAction: @escaping (RescopedState, RescopedAction) -> ScopedAction?
  ) -> Store<RescopedState, RescopedAction>
}

extension ScopedReducer: AnyScopedReducer {
  @inlinable
  func rescope<ScopedState, ScopedAction, RescopedState, RescopedAction>(
    _ store: Store<ScopedState, ScopedAction>,
    state toRescopedState: @escaping (ScopedState) -> RescopedState,
    action fromRescopedAction: @escaping (RescopedState, RescopedAction) -> ScopedAction?
  ) -> Store<RescopedState, RescopedAction> {
    let fromScopedAction = self.fromScopedAction as! (ScopedState, ScopedAction) -> RootAction?
    let reducer = ScopedReducer<RootState, RootAction, RescopedState, RescopedAction>(
      rootStore: self.rootStore,
      state: { _ in toRescopedState(store.state.value) },
      action: { fromRescopedAction($0, $1).flatMap { fromScopedAction(store.state.value, $0) } },
      parentStores: self.parentStores + [store]
    )
    let childStore = Store<RescopedState, RescopedAction>(
      initialState: toRescopedState(store.state.value),
      reducer: reducer
    )
    childStore.parentCancellable = store.state
      .skip(1)
      .subscribe { [weak childStore] newValue in
        guard !reducer.isSending else { return }
        childStore?.state.accept(toRescopedState(newValue))
      }
    return childStore
  }
}
#else
private protocol AnyStoreScope {
  func rescope<ScopedState, ScopedAction, RescopedState, RescopedAction>(
    _ store: Store<ScopedState, ScopedAction>,
    state toRescopedState: @escaping (ScopedState) -> RescopedState,
    action fromRescopedAction: @escaping (RescopedState, RescopedAction) -> ScopedAction?
  ) -> Store<RescopedState, RescopedAction>
}

private struct StoreScope<RootState, RootAction>: AnyStoreScope {
  let root: Store<RootState, RootAction>
  let fromScopedAction: Any

  init(root: Store<RootState, RootAction>) {
    self.init(
      root: root,
      fromScopedAction: { (state: RootState, action: RootAction) -> RootAction? in action }
    )
  }

  private init<ScopedState, ScopedAction>(
    root: Store<RootState, RootAction>,
    fromScopedAction: @escaping (ScopedState, ScopedAction) -> RootAction?
  ) {
    self.root = root
    self.fromScopedAction = fromScopedAction
  }

  func rescope<ScopedState, ScopedAction, RescopedState, RescopedAction>(
    _ scopedStore: Store<ScopedState, ScopedAction>,
    state toRescopedState: @escaping (ScopedState) -> RescopedState,
    action fromRescopedAction: @escaping (RescopedState, RescopedAction) -> ScopedAction?
  ) -> Store<RescopedState, RescopedAction> {
    let fromScopedAction = self.fromScopedAction as! (ScopedState, ScopedAction) -> RootAction?

    var isSending = false
    let rescopedStore = Store<RescopedState, RescopedAction>(
      initialState: toRescopedState(scopedStore.state.value),
      reducer: .init { rescopedState, rescopedAction, _ in
        isSending = true
        defer { isSending = false }
        guard
          let scopedAction = fromRescopedAction(rescopedState, rescopedAction),
          let rootAction = fromScopedAction(scopedStore.state.value, scopedAction)
        else { return .none }
        let task = self.root.send(rootAction)
        rescopedState = toRescopedState(scopedStore.state.value)
        if let task = task {
          return .fireAndForget { await task.cancellableValue }
        } else {
          return .none
        }
      },
      environment: ()
    )
    rescopedStore.parentCancellable = scopedStore.state
      .dropFirst()
      .sink { [weak rescopedStore] newValue in
        guard !isSending else { return }
        rescopedStore?.state.value = toRescopedState(newValue)
      }
    rescopedStore.scope = StoreScope<RootState, RootAction>(
      root: self.root,
      fromScopedAction: {
        fromRescopedAction($0, $1).flatMap { fromScopedAction(scopedStore.state.value, $0) }
      }
    )
    return rescopedStore
  }
}
#endif

