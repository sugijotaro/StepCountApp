//
//  StepServiceError.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import Combine

enum StepServiceError: Error {
    case noProviderAvailable
    case permissionDenied
    case dataNotAvailable
}

enum StepDataSource {
    case healthKit
    case coreMotion
    case hybrid
}

struct StepData {
    let steps: Int
    let source: StepDataSource
    let date: Date
}

protocol StepServiceProtocol {
    func requestPermissions() async throws
    func fetchTodaySteps() async throws -> StepData
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> StepData
    func fetchLastNDaysSteps(_ days: Int) async throws -> [Date: StepData]
    func fetchStepsForSpecificDate(_ date: Date) async throws -> StepData
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: StepData]
    func fetchMonthlySteps(for date: Date) async throws -> [Date: StepData]
    func fetchWeeklySteps(for date: Date) async throws -> [Date: StepData]
    func fetchYearlySteps(for year: Int) async throws -> [Date: StepData]
    func startRealtimeStepUpdates(handler: @escaping (StepData) -> Void)
    func stopRealtimeStepUpdates()
}

class StepService: StepServiceProtocol {
    private let healthKitProvider = HealthKitStepProvider()
    private let coreMotionProvider = CoreMotionStepProvider()
    
    private var realtimeUpdateStartDate: Date?
    
    func requestPermissions() async throws {
        var errors: [Error] = []
        
        if healthKitProvider.isAvailable {
            do {
                try await healthKitProvider.requestPermission()
            } catch {
                errors.append(error)
            }
        }
        
        if coreMotionProvider.isAvailable {
            do {
                try await coreMotionProvider.requestPermission()
            } catch {
                errors.append(error)
            }
        }
        
        if !hasAnyProviderAvailable() {
            throw StepServiceError.noProviderAvailable
        }
    }
    
    func fetchTodaySteps() async throws -> StepData {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> StepData {
        let daysFromToday = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        
        if daysFromToday <= 7 && coreMotionProvider.isAvailable {
            if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
                return try await fetchHybridSteps(from: startDate, to: endDate)
            } else {
                let steps = try await coreMotionProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: steps, source: .coreMotion, date: endDate)
            }
        } else if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
            let steps = try await healthKitProvider.fetchSteps(from: startDate, to: endDate)
            return StepData(steps: steps, source: .healthKit, date: endDate)
        } else {
            throw StepServiceError.noProviderAvailable
        }
    }
    
    func fetchLastNDaysSteps(_ days: Int) async throws -> [Date: StepData] {
        guard hasAnyProviderAvailable() else {
            throw StepServiceError.noProviderAvailable
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        var result: [Date: StepData] = [:]
        
        for i in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: endDate)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            
            do {
                let stepData = try await fetchSteps(from: dayStart, to: dayEnd)
                result[dayStart] = stepData
            } catch {
                continue
            }
        }
        
        return result
    }
    
    func startRealtimeStepUpdates(handler: @escaping (StepData) -> Void) {
        guard coreMotionProvider.isAvailable else { return }
        
        let startDate = Date()
        realtimeUpdateStartDate = startDate
        
        coreMotionProvider.startRealtimeStepUpdates(from: startDate) { steps in
            let stepData = StepData(steps: steps, source: .coreMotion, date: Date())
            handler(stepData)
        }
    }
    
    func stopRealtimeStepUpdates() {
        coreMotionProvider.stopRealtimeStepUpdates()
        realtimeUpdateStartDate = nil
    }
    
    private func fetchHybridSteps(from startDate: Date, to endDate: Date) async throws -> StepData {
        async let healthKitSteps = healthKitProvider.fetchSteps(from: startDate, to: endDate)
        async let coreMotionSteps = coreMotionProvider.fetchSteps(from: startDate, to: endDate)
        
        do {
            let (hkSteps, cmSteps) = try await (healthKitSteps, coreMotionSteps)
            
            let selectedSteps = max(hkSteps, cmSteps)
            
            return StepData(steps: selectedSteps, source: .hybrid, date: endDate)
        } catch {
            do {
                let hkSteps = try await healthKitProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: hkSteps, source: .healthKit, date: endDate)
            } catch {
                let cmSteps = try await coreMotionProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: cmSteps, source: .coreMotion, date: endDate)
            }
        }
    }
    
    func fetchStepsForSpecificDate(_ date: Date) async throws -> StepData {
        let daysFromToday = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        
        if daysFromToday <= 7 && coreMotionProvider.isAvailable {
            if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
                async let healthKitSteps = healthKitProvider.fetchStepsForSpecificDate(date)
                async let coreMotionSteps = coreMotionProvider.fetchStepsForSpecificDate(date)
                
                do {
                    let (hkSteps, cmSteps) = try await (healthKitSteps, coreMotionSteps)
                    let selectedSteps = max(hkSteps, cmSteps)
                    return StepData(steps: selectedSteps, source: .hybrid, date: date)
                } catch {
                    let hkSteps = try await healthKitProvider.fetchStepsForSpecificDate(date)
                    return StepData(steps: hkSteps, source: .healthKit, date: date)
                }
            } else {
                let steps = try await coreMotionProvider.fetchStepsForSpecificDate(date)
                return StepData(steps: steps, source: .coreMotion, date: date)
            }
        } else if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
            let steps = try await healthKitProvider.fetchStepsForSpecificDate(date)
            return StepData(steps: steps, source: .healthKit, date: date)
        } else {
            throw StepServiceError.noProviderAvailable
        }
    }
    
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable && healthKitProvider.isAuthorized else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchStepsForDateRange(from: startDate, to: endDate)
        
        var result: [Date: StepData] = [:]
        for (date, steps) in healthKitSteps {
            result[date] = StepData(steps: steps, source: .healthKit, date: date)
        }
        
        return result
    }
    
    func fetchMonthlySteps(for date: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable && healthKitProvider.isAuthorized else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchMonthlySteps(for: date)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    func fetchWeeklySteps(for date: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable && healthKitProvider.isAuthorized else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchWeeklySteps(for: date)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    func fetchYearlySteps(for year: Int) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable && healthKitProvider.isAuthorized else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchYearlySteps(for: year)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    private func hasAnyProviderAvailable() -> Bool {
        return (healthKitProvider.isAvailable && healthKitProvider.isAuthorized) ||
        coreMotionProvider.isAvailable
    }
}
