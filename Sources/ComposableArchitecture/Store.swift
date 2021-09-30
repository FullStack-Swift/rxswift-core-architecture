import Foundation
import RxRelay
import RxSwift

/// Store
public final class Store<State, Action> {
    /// synchronousActionsToSend
    private var synchronousActionsToSend: [Action] = []
    /// isSending
    private var isSending = false
    /// parentDisposable
    private var parentDisposable: Disposable?
    /// effectDisposables
    var effectDisposables = CompositeDisposable()
    /// reducer
    private let reducer: (inout State, Action) -> Effect<Action>
    /// stateRelay
    private var stateRelay: BehaviorRelay<State>
    /// state
    public private(set) var state: State {
        get { return stateRelay.value }
        set { stateRelay.accept(newValue) }
    }
    /// observable state
    var observable: Observable<State> {
        return stateRelay.asObservable()
    }
    
    deinit {
        parentDisposable?.dispose()
        effectDisposables.dispose()
    }
    
    
    
    /// Store
    public convenience init<Environment>(
        initialState: State,
        reducer: Reducer<State, Action, Environment>,
        environment: Environment
    ) {
        self.init(initialState: initialState,reducer: { reducer.run(&$0, $1, environment) })
    }
    
    /// scope
    /// - Returns: Store
    public func scope<LocalState, LocalAction>(
        state toLocalState: @escaping (State) -> LocalState,
        action fromLocalAction: @escaping (LocalAction) -> Action
    ) -> Store<LocalState, LocalAction> {
        let localStore = Store<LocalState, LocalAction>(
            initialState: toLocalState(self.state),
            reducer: { localState, localAction in
                self.send(fromLocalAction(localAction))
                localState = toLocalState(self.state)
                return .none
            }
        )
        localStore.parentDisposable = self.observable
            .subscribe(onNext: { [weak localStore] newValue in localStore?.state = toLocalState(newValue)
            })
        return localStore
    }
    
    /// scope
    /// - Returns: Store
    public func scope<LocalState>(
        state toLocalState: @escaping (State) -> LocalState
    ) -> Store<LocalState, Action> {
        self.scope(state: toLocalState, action: { $0 })
    }
    
    /// publisherScope
    /// - Returns: Effect Store
    public func publisherScope<LocalState, LocalAction>(
        state toLocalState: @escaping (Observable<State>) -> Observable<LocalState>,
        action fromLocalAction: @escaping (LocalAction) -> Action
    ) -> Effect<Store<LocalState, LocalAction>> {
        
        func extractLocalState(_ state: State) -> LocalState? {
            var localState: LocalState?
            _ = toLocalState(Observable.just(state)).subscribe(onNext: { localState = $0 })
            return localState
        }
        
        return toLocalState(self.observable)
            .map { localState in
                let localStore = Store<LocalState, LocalAction>(
                    initialState: localState,
                    reducer: { localState, localAction in
                        self.send(fromLocalAction(localAction))
                        localState = extractLocalState(self.state) ?? localState
                        return .none
                    })
                
                localStore.parentDisposable = self.observable
                    .subscribe(onNext: { [weak localStore] state in
                        guard let localStore = localStore else { return }
                        localStore.state = extractLocalState(state) ?? localStore.state
                    })
                
                return localStore
            }
            .eraseToEffect()
    }
    
    /// publisherScope
    /// - Returns: Effect Store
    public func publisherScope<LocalState>(
        state toLocalState: @escaping (Observable<State>) -> Observable<LocalState>
    ) -> Effect<Store<LocalState, Action>> {
        self.publisherScope(state: toLocalState, action: { $0 })
    }
    
    /// send action
    /// - Parameter action: action
    func send(_ action: Action) {
        self.synchronousActionsToSend.append(action)
        
        while !self.synchronousActionsToSend.isEmpty {
            let action = self.synchronousActionsToSend.removeFirst()
            
            if self.isSending {
                print("isSending")
            }
            self.isSending = true
            let effect = self.reducer(&self.state, action)
            self.isSending = false
            
            var didComplete = false
            var isProcessingEffects = true
            var disposeKey: CompositeDisposable.DisposeKey?
            
            let effectDisposable = effect.subscribe(
                onNext: { [weak self] action in
                    if isProcessingEffects {
                        self?.synchronousActionsToSend.append(action)
                    } else {
                        self?.send(action)
                    }
                },
                onError: { err in
                    print("\(err.localizedDescription)")
                },
                onCompleted: { [weak self] in
                    didComplete = true
                    if let disposeKey = disposeKey {
                        self?.effectDisposables.remove(for: disposeKey)
                    }
                }
            )
            
            isProcessingEffects = false
            
            if !didComplete {
                disposeKey = effectDisposables.insert(effectDisposable)
            }
        }
    }
    
    /// stateless
    public var stateless: Store<Void, Action> {
        self.scope(state: { _ in () })
    }
    
    /// actionless
    public var actionless: Store<State, Never> {
        func absurd<A>(_ never: Never) -> A {}
        return self.scope(state: { $0 }, action: absurd)
    }
    
    /// Effect
    /// - Parameters:
    ///   - initialState: initialState
    ///   - reducer: reducer
    private init(initialState: State, reducer: @escaping (inout State, Action) -> Effect<Action>) {
        self.stateRelay = BehaviorRelay(value: initialState)
        self.reducer = reducer
        self.state = initialState
    }
}
