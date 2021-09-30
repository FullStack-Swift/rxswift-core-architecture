import Foundation
import RxSwift

extension Effect where Value: RxAbstractInteger {
    /// timer
    /// - Parameters:
    ///   - id: id
    ///   - interval: interval
    ///   - scheduler: scheduler
    /// - Returns: Effect
  public static func timer(
    id: AnyHashable,
    every interval: RxTimeInterval,
    on scheduler: SchedulerType
  ) -> Effect {

    return
      Observable
      .interval(interval, scheduler: scheduler)
      .eraseToEffect()
      .cancellable(id: id)
  }
}
