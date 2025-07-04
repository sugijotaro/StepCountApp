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
    
    private func hasAnyProviderAvailable() -> Bool {
        return (healthKitProvider.isAvailable && healthKitProvider.isAuthorized) ||
        coreMotionProvider.isAvailable
    }
}
