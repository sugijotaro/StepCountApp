//
//  HealthKitStepError.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import HealthKit

enum HealthKitStepError: Error {
    case notAvailable
    case unauthorized
    case dataNotAvailable
}

class HealthKitStepProvider {
    private let healthStore = HKHealthStore()
    
    var isAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    var isAuthorized: Bool {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return false }
        return healthStore.authorizationStatus(for: stepCountType) == .sharingAuthorized
    }
    
    func requestPermission() async throws {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitStepError.notAvailable
        }
        
        let typesToRead: Set<HKObjectType> = [stepCountType]
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitStepError.unauthorized)
                }
            }
        }
    }
    
    func fetchTodaySteps() async throws -> Int {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        guard isAuthorized else {
            throw HealthKitStepError.unauthorized
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        guard isAuthorized else {
            throw HealthKitStepError.unauthorized
        }
        
        guard let quantityType = HKSampleType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitStepError.notAvailable
        }
        
        let periodPredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate
        )
        
        let predicate = HKSamplePredicate.quantitySample(
            type: quantityType,
            predicate: periodPredicate
        )
        
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum
        )
        
        let result = try await descriptor.result(for: healthStore)
        
        let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        return Int(sum)
    }
    
    func fetchStepsForLastNDays(_ days: Int) async throws -> [Date: Int] {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        guard isAuthorized else {
            throw HealthKitStepError.unauthorized
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        
        var result: [Date: Int] = [:]
        
        for i in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: endDate)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            
            let steps = try await fetchSteps(from: dayStart, to: dayEnd)
            result[dayStart] = steps
        }
        
        return result
    }
}
