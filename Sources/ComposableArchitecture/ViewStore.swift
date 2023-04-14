import RxRelay
import RxSwift

/// A ``ViewStore`` is an object that can observe state changes and send actions. They are most
/// commonly used in views, such as SwiftUI views, UIView or UIViewController, but they can be
/// used anywhere it makes sense to observe state and send actions.
///
/// In SwiftUI applications, a ``ViewStore`` is accessed most commonly using the ``WithViewStore``
/// view. It can be initialized with a store and a closure that is handed a view store and must
/// return a view to be rendered:
///
/// ```swift
/// var body: some View {
///   WithViewStore(self.store) { viewStore in
///     VStack {
///       Text("Current count: \(viewStore.count)")
///       Button("Increment") { viewStore.send(.incrementButtonTapped) }
///     }
///   }
/// }
/// ```
///
/// In UIKit applications a ``ViewStore`` can be created from a ``Store`` and then subscribed to for
/// state updates:
///
/// ```swift
/// let store: Store<State, Action>
/// let viewStore: ViewStore<State, Action>
///
/// init(store: Store<State, Action>) {
///   self.store = store
///   self.viewStore = ViewStore(store)
/// }
///
/// func viewDidLoad() {
///   super.viewDidLoad()
///
///   self.viewStore.publisher.count
///     .sink { [weak self] in self?.countLabel.text = $0 }
///     .store(in: &self.cancellables)
/// }
///
/// @objc func incrementButtonTapped() {
///   self.viewStore.send(.incrementButtonTapped)
/// }
/// ```
///
/// ### Thread safety
///
/// The ``ViewStore`` class is not thread-safe, and all interactions with it (and the store it was
/// derived from) must happen on the same thread. Further, for SwiftUI applications, all
/// interactions must happen on the _main_ thread. See the documentation of the ``Store`` class for
/// more information as to why this decision was made.
@dynamicMemberLookup
public final class ViewStore<ViewState, ViewAction> {
  private let _send: (ViewAction) -> Void
  fileprivate var _state: BehaviorRelay<ViewState>
  private var viewDisposable: Disposable?
  deinit {
    viewDisposable?.dispose()
  }
  /// Initializes a view store from a store.
  ///
  /// - Parameters:
  ///   - store: A store.
  ///   - isDuplicate: A function to determine when two `State` values are equal. When values are
  ///     equal, repeat view computations are removed.
  public init<State>(
    _ store: Store<State, ViewAction>,
    observe toViewState: @escaping (State) -> ViewState,
    removeDuplicates isDuplicate: @escaping (ViewState, ViewState) -> Bool
  ) {
    self._send = { store.send($0) }
    self._state = BehaviorRelay(value: toViewState(store.state.value))
    self.viewDisposable = store.state
      .map(toViewState)
      .distinctUntilChanged(isDuplicate).subscribe(onNext: { [weak self] in
        guard let self = self else { return }
        self._state.accept($0)
      })
  }
  /// Initializes a view store from a store which observes changes to state.
  ///
  /// It is recommended that the `observe` argument transform the store's state into the bare
  /// minimum of data needed for the feature to do its job in order to not hinder performance.
  /// This is especially true for root level features, and less important for leaf features.
  ///
  /// To read more about this performance technique, read the <doc:Performance> article.
  ///
  /// - Parameters:
  ///   - store: A store.
  ///   - toViewState: A transformation of `ViewState` to the state that will be observed for
  ///   changes.
  ///   - fromViewAction: A transformation of `ViewAction` that describes what actions can be sent.
  ///   - isDuplicate: A function to determine when two `State` values are equal. When values are
  ///   equal, repeat view computations are removed.
  public init<State, Action>(
    _ store: Store<State, Action>,
    observe toViewState: @escaping (State) -> ViewState,
    send fromViewAction: @escaping (ViewAction) -> Action,
    removeDuplicates isDuplicate: @escaping (ViewState, ViewState) -> Bool
  ) {
    self._send = { store.send(fromViewAction($0)) }
    self._state = BehaviorRelay(value: toViewState(store.state.value))
    self.viewDisposable = store.state
      .map(toViewState)
      .distinctUntilChanged(isDuplicate).subscribe(onNext: { [weak self] in
        guard let self = self else { return }
        self._state.accept($0)
      })
  }

  /// Initializes a view store from a store.
  ///
  /// > Warning: This initializer is deprecated. Use
  /// ``ViewStore/init(_:observe:removeDuplicates:)`` to make state observation explicit.
  /// >
  /// > When using ``ViewStore`` you should take care to observe only the pieces of state that
  /// your view needs to do its job, especially towards the root of the application. See
  /// <doc:Performance> for more details.
  ///
  /// - Parameters:
  ///   - store: A store.
  ///   - isDuplicate: A function to determine when two `State` values are equal. When values are
  ///     equal, repeat view computations are removed.
  @available(
    iOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:removeDuplicates:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    macOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:removeDuplicates:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    tvOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:removeDuplicates:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    watchOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:removeDuplicates:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  public init(
    _ store: Store<ViewState, ViewAction>,
    removeDuplicates isDuplicate: @escaping (ViewState, ViewState) -> Bool
  ) {
    self._send = { store.send($0) }
    self._state = BehaviorRelay(value: store.state.value)
    self.viewDisposable = store.state
      .distinctUntilChanged(isDuplicate)
      .subscribe(onNext: { [weak self] in
        guard let self = self else { return }
        self._state.accept($0)
      })
  }

  init(_ viewStore: ViewStore<ViewState, ViewAction>) {
    self._send = viewStore._send
    self._state = viewStore._state
    self.viewDisposable = viewStore.viewDisposable
  }

  /// A publisher that emits when state changes.
  ///
  /// This publisher supports dynamic member lookup so that you can pluck out a specific field in
  /// the state:
  ///
  /// ```swift
  /// viewStore.publisher.alert
  ///   .sink { ... }
  /// ```
  ///
  /// When the emission happens the ``ViewStore``'s state has been updated, and so the following
  /// precondition will pass:
  ///
  /// ```swift
  /// viewStore.publisher
  ///   .sink { precondition($0 == viewStore.state) }
  /// ```
  ///
  /// This means you can either use the value passed to the closure or you can reach into
  /// `viewStore.state` directly.
  ///
  /// - Note: Due to a bug in Combine (or feature?), the order you `.sink` on a publisher has no
  ///   bearing on the order the `.sink` closures are called. This means the work performed inside
  ///   `viewStore.publisher.sink` closures should be completely independent of each other. Later
  ///   closures cannot assume that earlier ones have already run.
  public var publisher: StorePublisher<ViewState> {
    StorePublisher(viewStore: self)
  }
  /// The current state.
  public var state: ViewState {
    self._state.value
  }
  /// Returns the resulting value of a given key path.
  public subscript<LocalState>(dynamicMember keyPath: KeyPath<ViewState, LocalState>) -> LocalState {
    self._state.value[keyPath: keyPath]
  }
  /// The Binder action.
  public var action: Binder<ViewAction> {
    Binder(self) { weakSelf, action in
      weakSelf.send(action)
    }
  }
  /// Sends an action to the store.
  ///
  /// ``ViewStore`` is not thread safe and you should only send actions to it from the main thread.
  /// If you are wanting to send actions on background threads due to the fact that the reducer
  /// is performing computationally expensive work, then a better way to handle this is to wrap
  /// that work in an ``Effect`` that is performed on a background thread so that the result can
  /// be fed back into the store.
  ///
  /// - Parameter action: An action.
  public func send(_ action: ViewAction) {
    self._send(action)
  }
}

/// A convenience type alias for referring to a view store of a given reducer's domain.
///
/// Instead of specifying two generics:
///
/// ```swift
/// let viewStore: ViewStore<Feature.State, Feature.Action>
/// ```
///
/// You can specify a single generic:
///
/// ```swift
/// let viewStore: ViewStoreOf<Feature>
/// ```
//public typealias ViewStoreOf<R: ReducerProtocol> = ViewStore<R.State, R.Action>

extension ViewStore where ViewState: Equatable {
  public convenience init<State>(
    _ store: Store<State, ViewAction>,
    observe toViewState: @escaping (State) -> ViewState
  ) {
    self.init(store, observe: toViewState, removeDuplicates: ==)
  }

  public convenience init<State, Action>(
    _ store: Store<State, Action>,
    observe toViewState: @escaping (State) -> ViewState,
    send fromViewAction: @escaping (ViewAction) -> Action
  ) {
    self.init(store, observe: toViewState, send: fromViewAction, removeDuplicates: ==)
  }

  /// Initializes a view store from a store.
  ///
  /// > Warning: This initializer is deprecated. Use
  /// ``ViewStore/init(_:observe:)`` to make state observation explicit.
  /// >
  /// > When using ``ViewStore`` you should take care to observe only the pieces of state that
  /// your view needs to do its job, especially towards the root of the application. See
  /// <doc:Performance> for more details.
  ///
  /// - Parameters:
  ///   - store: A store.
  @available(
    iOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    macOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    tvOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  @available(
    watchOS,
    deprecated: 9999.0,
    message:
      """
      Use 'init(_:observe:)' to make state observation explicit.

      When using ViewStore you should take care to observe only the pieces of state that your view needs to do its job, especially towards the root of the application. See the performance article for more details:

      https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/performance#View-stores
      """
  )
  public convenience init(_ store: Store<ViewState, ViewAction>) {
    self.init(store, removeDuplicates: ==)
  }
}

extension ViewStore where ViewState == Void {
  public convenience init(_ store: Store<Void, ViewAction>) {
    self.init(store, removeDuplicates: ==)
  }
}

/// A publisher of store state.
@dynamicMemberLookup
public struct StorePublisher<State>: ObservableType {
  public typealias Element = State
  public let upstream: Observable<State>
  public let viewStore: Any
  
  fileprivate init<Action>(viewStore: ViewStore<State, Action>) {
    self.viewStore = viewStore
    self.upstream = viewStore._state.asObservable()
  }
  
  public func subscribe<Observer>(_ observer: Observer) -> Disposable where Observer: ObserverType, Element == Observer.Element {
    return upstream
      .do(onDispose: {
        _ = viewStore
      })
      .subscribe(observer)
  }
  
  private init(_ upstream: Observable<State>, viewStore: Any) {
    self.upstream = upstream
    self.viewStore = viewStore
  }
  
  /// Returns the resulting publisher of a given key path.
  public subscript<LocalState>(
    dynamicMember keyPath: KeyPath<State, LocalState>
  ) -> StorePublisher<LocalState> where LocalState: Equatable {
    .init(self.upstream.map { $0[keyPath: keyPath] }.distinctUntilChanged(), viewStore: viewStore)
  }
}
