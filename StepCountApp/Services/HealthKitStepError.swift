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
        let status = healthStore.authorizationStatus(for: stepCountType)
        // HealthKitでは、プライバシー保護のため.notDeterminedでも実際には許可されている場合がある
        // .sharingDeniedの場合のみ明確に拒否されている
        return status != .sharingDenied
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
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
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
    
    func fetchStepsForSpecificDate(_ date: Date) async throws -> Int {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            throw HealthKitStepError.dataNotAvailable
        }
        
        // Try to fetch data directly without checking authorization status first
        // HealthKit will handle authorization internally
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: Int] {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: startDate)
        let startOfEndDate = calendar.startOfDay(for: endDate)
        
        var result: [Date: Int] = [:]
        var currentDate = startOfStartDate
        
        while currentDate <= startOfEndDate {
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            
            do {
                let steps = try await fetchSteps(from: currentDate, to: nextDate)
                result[currentDate] = steps
            } catch {
                result[currentDate] = 0
            }
            
            currentDate = nextDate
        }
        
        return result
    }
    
    func fetchMonthlySteps(for date: Date) async throws -> [Date: Int] {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            throw HealthKitStepError.dataNotAvailable
        }
        
        return try await fetchStepsForDateRange(from: startOfMonth, to: endOfMonth)
    }
    
    func fetchWeeklySteps(for date: Date) async throws -> [Date: Int] {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        let calendar = Calendar.current
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            throw HealthKitStepError.dataNotAvailable
        }
        
        return try await fetchStepsForDateRange(from: startOfWeek, to: endOfWeek)
    }
    
    func fetchYearlySteps(for year: Int) async throws -> [Date: Int] {
        guard isAvailable else {
            throw HealthKitStepError.notAvailable
        }
        
        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            throw HealthKitStepError.dataNotAvailable
        }
        
        return try await fetchStepsForDateRange(from: startOfYear, to: endOfYear)
    }
}
