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

@MainActor
public final class CoreMotionStepProvider: CoreMotionStepProviding {
    private let pedometer = CMPedometer()
    
    public var isAvailable: Bool {
        return CMPedometer.isStepCountingAvailable()
    }
    
    public func requestPermission() async throws {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
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

        // `Task.detached`を使い、現在のアクター（@MainActor）から処理を切り離す。
        // これにより、バックグラウンドで安全に待機できる。
        let task = Task.detached {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                // このクロージャはバックグラウンドタスク内で実行される
                self.pedometer.queryPedometerData(from: startDate, to: endDate) { data, error in
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
        return try await task.value
    }
    
    public func startRealtimeStepUpdates(from startDate: Date, handler: @escaping (Int) -> Void) {
        guard isAvailable else { return }
        
        pedometer.startUpdates(from: startDate) { data, error in
            if let steps = data?.numberOfSteps {
                Task { @MainActor in
                    handler(steps.intValue)
                }
            }
        }
    }
    
    public func stopRealtimeStepUpdates() {
        pedometer.stopUpdates()
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
}
