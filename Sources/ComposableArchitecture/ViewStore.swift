import RxRelay
import RxSwift

@dynamicMemberLookup
public final class ViewStore<State, Action> {
    /// _send
    private let _send: (Action) -> Void
    /// _state
    fileprivate var _state: BehaviorRelay<State>
    /// viewDisposable
    private var viewDisposable: Disposable?
    
    deinit {
        viewDisposable?.dispose()
    }
    
    /// ViewStore
    /// - Parameters:
    ///   - store: store
    ///   - isDuplicate: isDuplicate
    public init(_ store: Store<State, Action>, removeDuplicates isDuplicate: @escaping (State, State) -> Bool) {
        self._state = BehaviorRelay(value: store.state)
        self._send = store.send
        self.viewDisposable = store.observable.observe(on: MainScheduler.instance)
            .distinctUntilChanged(isDuplicate).subscribe(onNext: { [weak self] in
                guard let self = self else { return }
                self._state.accept($0)
            })
    }
    
    /// StorePublisher
    public var publisher: StorePublisher<State> {
        StorePublisher(viewStore: self)
    }
    
    /// state
    public var state: State {
        self._state.value
    }
    
    /// action
    public var action: Binder<Action> {
        Binder(self) { weakSelf, action in
            weakSelf.send(action)
        }
    }
    
    /// send action
    /// - Parameter action: action
    public func send(_ action: Action) {
        self._send(action)
    }
    
    public subscript<LocalState>(dynamicMember keyPath: KeyPath<State, LocalState>) -> LocalState {
        self._state.value[keyPath: keyPath]
    }
}

extension ViewStore where State: Equatable {
    /// ViewStore
    /// - Parameter store: store
    public convenience init(_ store: Store<State, Action>) {
        self.init(store, removeDuplicates: ==)
    }
}

extension ViewStore where State == Void {
    /// ViewStore
    /// - Parameter store: store
    public convenience init(_ store: Store<Void, Action>) {
        self.init(store, removeDuplicates: ==)
    }
}

@dynamicMemberLookup
/// StorePublisher
public struct StorePublisher<State>: ObservableType {
    public typealias Element = State
    /// upstream
    public let upstream: Observable<State>
    /// viewStore
    public let viewStore: Any
    /// disposeBag
    private let disposeBag = DisposeBag()
    
    /// StorePublisher
    fileprivate init<Action>(viewStore: ViewStore<State, Action>) {
        self.viewStore = viewStore
        self.upstream = viewStore._state.asObservable()
    }
    
    /// subscribe
    /// - Returns: Disposable
    public func subscribe<Observer>(_ observer: Observer) -> Disposable where Observer: ObserverType, Element == Observer.Element {
        upstream.asObservable().subscribe { event in
            switch event {
            case .error, .completed:
                _ = viewStore
            default:
                break
            }
        }
        .disposed(by: disposeBag)
        return upstream.subscribe(observer)
    }
    
    /// StorePublisher
    /// - Parameters:
    ///   - upstream: upstream
    ///   - viewStore: viewStore
    private init(_ upstream: Observable<State>, viewStore: Any) {
        self.upstream = upstream
        self.viewStore = viewStore
    }
    
    public subscript<LocalState>(dynamicMember keyPath: KeyPath<State, LocalState>) -> StorePublisher<LocalState> where LocalState: Equatable {
        .init(self.upstream.map { $0[keyPath: keyPath] }.distinctUntilChanged(), viewStore: viewStore)
    }
}
