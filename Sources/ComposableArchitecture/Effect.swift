import Foundation
import RxSwift

public struct Effect<Value>: ObservableType {
    
    public typealias Element = Value
    
    public let upstream: Observable<Value>
    
    /// Effect
    /// - Parameter observable: observable
    public init(_ observable: Observable<Value>) {
        self.upstream = observable
    }
    
    /// subscribe
    /// - Returns: Disposable
    public func subscribe<Observer>(_ observer: Observer) -> Disposable where Observer: ObserverType, Element == Observer.Element {
        upstream.subscribe(observer)
    }
    
    /// Effect
    /// - Parameter value: value
    public init(value: Value) {
        self.init(Observable.just(value))
    }
    
    /// Effect
    /// - Parameter error: error
    public init(error: Error) {
        self.init(Observable.error(error))
    }
    
    
    /// Effect
    public static var none: Self {
        Observable.empty().eraseToEffect()
    }
    
    /// future
    /// - Parameter attemptToFulfill: result
    /// - Returns: Effect
    public static func future(_ attemptToFulfill: @escaping (@escaping (Result<Value, Error>) -> Void) -> Void) -> Self {
        Observable.create { observer in
            attemptToFulfill { result in
                switch result {
                case let .success(output):
                    observer.onNext(output)
                    observer.onCompleted()
                case let .failure(error):
                    observer.onError(error)
                }
            }
            return Disposables.create()
        }
        .eraseToEffect()
    }
    
    /// result
    /// - Parameter attemptToFulfill: result
    /// - Returns: Effect
    public static func result(_ attemptToFulfill: @escaping () -> Result<Value, Error>) -> Self {
        Observable.create { observer in
            switch attemptToFulfill() {
            case let .success(output):
                observer.onNext(output)
                observer.onCompleted()
            case let .failure(error):
                observer.onError(error)
            }
            return Disposables.create()
        }
        .eraseToEffect()
    }
    
    /// run
    /// - Parameter work: work description
    /// - Returns: Effect
    public static func run(_ work: @escaping (AnyObserver<Value>) -> Disposable) -> Self {
        Observable.create(work).eraseToEffect()
    }
    
    /// concatenate
    /// - Parameter effects: effects description
    /// - Returns: Effect
    public static func concatenate(_ effects: Effect...) -> Effect {
        .concatenate(effects)
    }
    
    /// concatenate
    /// - Returns: Effect
    public static func concatenate<C: Collection>(_ effects: C) -> Effect where C.Element == Effect {
        guard let first = effects.first else { return .none }
        return effects
            .dropFirst()
            .reduce(into: first) { effects, effect in
                effects = effects.concat(effect).eraseToEffect()
            }
    }
    
    /// merge
    /// - Parameter effects: effects description
    /// - Returns: Effect
    public static func merge(_ effects: Effect...) -> Effect {
        .merge(effects)
    }
    
    /// merge
    /// - Returns: Effect
    public static func merge<S: Sequence>(_ effects: S) -> Effect where S.Element == Effect {
        Observable
            .merge(effects.map { $0.asObservable() })
            .eraseToEffect()
    }
    
    /// fireAndForget
    /// - Parameter work: work description
    /// - Returns: Effect
    public static func fireAndForget(_ work: @escaping () -> Void) -> Effect {
        return Effect(
            Observable.deferred {
                work()
                return Observable<Value>.empty()
            })
    }
    
    /// map
    /// - Returns: Effect
    public func map<T>(_ transform: @escaping (Value) -> T) -> Effect<T> {
        .init(self.map(transform))
    }
}

extension Effect where Value == Never {
    
    /// fireAndForget
    /// - Returns: Effect
    public func fireAndForget<T>() -> Effect<T> {
        func absurd<A>(_ never: Never) -> A {}
        return self.map(absurd)
    }
}

extension ObservableType {
    
    /// eraseToEffect
    /// - Returns: Effect
    public func eraseToEffect() -> Effect<Element> {
        Effect(asObservable())
    }
    
    /// catchToEffect
    /// - Returns: Effect
    public func catchToEffect() -> Effect<Result<Element, Error>> {
        self.map(Result<Element, Error>.success)
            .catch { Observable<Result<Element, Error>>.just(Result.failure($0)) }
            .eraseToEffect()
    }
}

extension Observable {
    /// assign
    /// - Returns: Disposable
    @discardableResult
    public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root,Element>, on object: Root) -> Disposable {
        subscribe(onNext: { value in
            object[keyPath: keyPath] = value
        })
    }
}
