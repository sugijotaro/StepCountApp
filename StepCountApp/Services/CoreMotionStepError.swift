//
//  CoreMotionStepError.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import CoreMotion

enum CoreMotionStepError: Error {
    case notAvailable
    case unauthorized
    case dataNotAvailable
}

class CoreMotionStepProvider {
    private let pedometer = CMPedometer()
    
    var isAvailable: Bool {
        return CMPedometer.isStepCountingAvailable()
    }
    
    func requestPermission() async throws {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
    }
    
    func fetchTodaySteps() async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: startDate, to: endDate) { data, error in
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
    
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.notAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: startDate, to: endDate) { data, error in
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
    
    func startRealtimeStepUpdates(from startDate: Date, handler: @escaping (Int) -> Void) {
        guard isAvailable else { return }
        
        pedometer.startUpdates(from: startDate) { data, error in
            if let steps = data?.numberOfSteps {
                handler(steps.intValue)
            }
        }
    }
    
    func stopRealtimeStepUpdates() {
        pedometer.stopUpdates()
    }
}
