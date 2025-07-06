//
//  CoreMotionStepError.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import CoreMotion

public enum CoreMotionStepError: Error {
    case notAvailable
    case unauthorized
    case dataNotAvailable
}

// CMPedometerをラップする専用のアクター
actor PedometerActor {
    private let pedometer = CMPedometer()
    
    // コールバックベースのAPIをasync/awaitに変換する
    func query(from start: Date, to end: Date) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let steps = data?.numberOfSteps {
                    continuation.resume(returning: steps.intValue)
                } else {
                    continuation.resume(throwing: CoreMotionStepError.dataNotAvailable)
                }
            }
        }
    }
    
    // リアルタイム更新の開始・停止機能もアクター内に移動
    func startUpdates(from startDate: Date, withHandler handler: @escaping @Sendable (Int) -> Void) {
        pedometer.startUpdates(from: startDate) { data, error in
            if let steps = data?.numberOfSteps {
                handler(steps.intValue)
            }
        }
    }
    
    func stopUpdates() {
        pedometer.stopUpdates()
    }
}

public final class CoreMotionStepProvider: CoreMotionStepProviding, Sendable {
    private let pedometerActor = PedometerActor()
    
    public init() {}
    
    public var isAvailable: Bool {
        return CMPedometer.isStepCountingAvailable()
    }
    
    public func requestPermission() async throws {
        guard isAvailable else { throw CoreMotionStepError.notAvailable }
    }
    
    public func fetchTodaySteps() async throws -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        return try await self.fetchSteps(from: startDate, to: endDate)
    }
    
    public func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isAvailable else { throw CoreMotionStepError.notAvailable }
        return try await pedometerActor.query(from: startDate, to: endDate)
    }
    
    public func fetchStepsForSpecificDate(_ date: Date) async throws -> Int {
        guard isAvailable else { throw CoreMotionStepError.notAvailable }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            throw CoreMotionStepError.dataNotAvailable
        }
        
        let daysFromToday = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysFromToday > 7 { throw CoreMotionStepError.dataNotAvailable }
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    // アクターのメソッドを非同期で呼び出す
    public func startRealtimeStepUpdates(from startDate: Date, handler: @escaping @Sendable (Int) -> Void) {
        guard isAvailable else { return }
        Task {
            await pedometerActor.startUpdates(from: startDate, withHandler: handler)
        }
    }
    
    public func stopRealtimeStepUpdates() {
        Task {
            await pedometerActor.stopUpdates()
        }
    }
}
