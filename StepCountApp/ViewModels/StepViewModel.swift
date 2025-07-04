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
}
