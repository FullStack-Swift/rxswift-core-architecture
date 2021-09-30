import RxSwift

extension Effect {
    /// debounce
    /// - Parameters:
    ///   - id: id
    ///   - dueTime: dueTime
    ///   - scheduler: scheduler
    /// - Returns: Effect
  public func debounce(
    id: AnyHashable,
    for dueTime: RxTimeInterval,
    scheduler: SchedulerType
  ) -> Effect {
    Observable.just(())
      .delay(dueTime, scheduler: scheduler)
      .flatMap { self }
      .eraseToEffect()
      .cancellable(id: id, cancelInFlight: true)
  }
}
