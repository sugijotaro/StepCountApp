//
//  StepViewModel.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import SwiftUI

@MainActor
class StepViewModel: ObservableObject {
    @Published var todaySteps: StepData?
    @Published var realtimeSteps: StepData?
    @Published var weeklySteps: [Date: StepData] = [:]
    @Published var selectedDateSteps: StepData?
    @Published var monthlySteps: [Date: StepData] = [:]
    @Published var dateRangeSteps: [Date: StepData] = [:]
    @Published var selectedDate = Date()
    @Published var selectedMonth = Date()
    @Published var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRealtimeUpdating = false
    @Published var permissionStatus = PermissionStatus.notRequested
    
    enum PermissionStatus {
        case notRequested
        case requesting
        case granted
        case denied
    }
    
    private let stepService: StepServiceProtocol
    
    init(stepService: StepServiceProtocol = StepService()) {
        self.stepService = stepService
    }
    
    func requestPermissions() async {
        permissionStatus = .requesting
        do {
            try await stepService.requestPermissions()
            permissionStatus = .granted
        } catch {
            permissionStatus = .denied
            errorMessage = "Permission was denied: \(error.localizedDescription)"
        }
    }
    
    func fetchTodaySteps() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let stepData = try await stepService.fetchTodaySteps()
            todaySteps = stepData
        } catch {
            errorMessage = "Failed to fetch today's steps: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func fetchWeeklySteps() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let steps = try await stepService.fetchLastNDaysSteps(7)
            weeklySteps = steps
        } catch {
            errorMessage = "Failed to fetch weekly steps: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func startRealtimeUpdates() {
        guard !isRealtimeUpdating else { return }
        
        isRealtimeUpdating = true
        
        stepService.startRealtimeStepUpdates { [weak self] stepData in
            Task { @MainActor in
                self?.realtimeSteps = stepData
            }
        }
    }
    
    func stopRealtimeUpdates() {
        guard isRealtimeUpdating else { return }
        
        isRealtimeUpdating = false
        stepService.stopRealtimeStepUpdates()
    }
    
    func refresh() async {
        await fetchTodaySteps()
        await fetchWeeklySteps()
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func getStepCountDisplayString(for stepData: StepData?) -> String {
        guard let stepData = stepData else { return "---" }
        return "\(stepData.steps) steps"
    }
    
    func getDataSourceDisplayString(for stepData: StepData?) -> String {
        guard let stepData = stepData else { return "" }
        
        switch stepData.source {
        case .healthKit:
            return "HealthKit"
        case .coreMotion:
            return "CoreMotion"
        case .hybrid:
            return "Hybrid (HealthKit + CoreMotion)"
        }
    }
    
    func getWeeklyStepsArray() -> [(date: Date, stepData: StepData)] {
        return weeklySteps.sorted { $0.key < $1.key }.map { (date: $0.key, stepData: $0.value) }
    }
    
    func fetchStepsForSelectedDate() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let stepData = try await stepService.fetchStepsForSpecificDate(selectedDate)
            selectedDateSteps = stepData
        } catch let error as StepServiceError {
            switch error {
            case .noProviderAvailable:
                errorMessage = "No step counting provider available. Please check if HealthKit is supported on this device."
            case .permissionDenied:
                errorMessage = "HealthKit permission denied. Please grant permission in Settings > Health > Data Access & Devices."
            case .dataNotAvailable:
                errorMessage = "Step data not available for the selected date."
            }
        } catch let error as HealthKitStepError {
            switch error {
            case .notAvailable:
                errorMessage = "HealthKit is not available on this device."
            case .unauthorized:
                errorMessage = "HealthKit access not authorized. Please grant permission in Settings."
            case .dataNotAvailable:
                errorMessage = "No step data available for the selected date."
            }
        } catch {
            errorMessage = "Failed to fetch steps for selected date: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func fetchMonthlySteps() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let steps = try await stepService.fetchMonthlySteps(for: selectedMonth)
            monthlySteps = steps
        } catch let error as StepServiceError {
            switch error {
            case .noProviderAvailable:
                errorMessage = "HealthKit not available for monthly data."
            case .permissionDenied:
                errorMessage = "HealthKit permission required for monthly data."
            case .dataNotAvailable:
                errorMessage = "Monthly step data not available."
            }
        } catch {
            errorMessage = "Failed to fetch monthly steps: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func fetchDateRangeSteps() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let steps = try await stepService.fetchStepsForDateRange(from: startDate, to: endDate)
            dateRangeSteps = steps
        } catch let error as StepServiceError {
            switch error {
            case .noProviderAvailable:
                errorMessage = "HealthKit not available for date range data."
            case .permissionDenied:
                errorMessage = "HealthKit permission required for date range data."
            case .dataNotAvailable:
                errorMessage = "Date range step data not available."
            }
        } catch {
            errorMessage = "Failed to fetch date range steps: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func getMonthlyStepsArray() -> [(date: Date, stepData: StepData)] {
        return monthlySteps.sorted { $0.key < $1.key }.map { (date: $0.key, stepData: $0.value) }
    }
    
    func getDateRangeStepsArray() -> [(date: Date, stepData: StepData)] {
        return dateRangeSteps.sorted { $0.key < $1.key }.map { (date: $0.key, stepData: $0.value) }
    }
    
    func getTotalStepsInRange() -> Int {
        return dateRangeSteps.values.reduce(0) { $0 + $1.steps }
    }
    
    func getAverageStepsInRange() -> Int {
        let total = getTotalStepsInRange()
        let days = dateRangeSteps.count
        return days > 0 ? total / days : 0
    }
}
