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
}

// @MainActorは不要。Sendableに準拠させる。
public final class CoreMotionStepProvider: CoreMotionStepProviding, Sendable {
    // 専用アクターのインスタンスを保持する
    private let pedometerActor = PedometerActor()
    // リアルタイム更新用のPedometerは別途保持する
    private let realtimePedometer = CMPedometer()
    
    public init() {} // publicなイニシャライザを追加
    
    public var isAvailable: Bool {
        return CMPedometer.isStepCountingAvailable()
    }
    
    public func requestPermission() async throws {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
        // 権限要求のロジックは特に何もしない
    }
    
    public func fetchTodaySteps() async throws -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        return try await self.fetchSteps(from: startDate, to: endDate)
    }
    
    public func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
        // アクターのメソッドを呼び出すことで、安全に非同期処理を実行
        return try await pedometerActor.query(from: startDate, to: endDate)
    }
    
    public func fetchStepsForSpecificDate(_ date: Date) async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            throw CoreMotionStepError.dataNotAvailable
        }
        
        let daysFromToday = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        
        if daysFromToday > 7 {
            throw CoreMotionStepError.dataNotAvailable
        }
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    public func startRealtimeStepUpdates(from startDate: Date, handler: @escaping @Sendable (Int) -> Void) {
        guard isAvailable else { return }
        
        realtimePedometer.startUpdates(from: startDate) { data, error in
            if let steps = data?.numberOfSteps {
                // ハンドラは @Sendable である必要がある
                handler(steps.intValue)
            }
        }
    }
    
    public func stopRealtimeStepUpdates() {
        realtimePedometer.stopUpdates()
    }
}
