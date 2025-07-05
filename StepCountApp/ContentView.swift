//
//  ContentView.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import SwiftUI
import HealthKit
import CoreMotion

struct ContentView: View {
    @StateObject private var viewModel = StepViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    permissionSection
                    
                    todayStepsSection
                    
                    realtimeStepsSection
                    
                    weeklyStepsSection
                    
                    specificDateSection
                    
                    monthlyStepsSection
                    
                    dateRangeSection
                    
                    actionsSection
                }
                .padding()
            }
            .navigationTitle("StepCount Demo")
            .refreshable {
                await viewModel.refresh()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
        }
        .task {
            if viewModel.permissionStatus == .notRequested {
                await viewModel.requestPermissions()
            }
            await viewModel.fetchTodaySteps()
            await viewModel.fetchWeeklySteps()
        }
    }
    
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permission Status")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: permissionIcon)
                        .foregroundColor(permissionColor)
                    Text(permissionText)
                        .foregroundColor(permissionColor)
                    Spacer()
                }
                
                // Debug information
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("HealthKit Available: \(HKHealthStore.isHealthDataAvailable() ? "Yes" : "No")")
                        .font(.caption2)
                    Text("CoreMotion Available: \(CMPedometer.isStepCountingAvailable() ? "Yes" : "No")")
                        .font(.caption2)
                    Text("HealthKit Auth Status: \(healthKitAuthStatusText)")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var todayStepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Steps")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(viewModel.getStepCountDisplayString(for: viewModel.todaySteps))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Data Source: \(viewModel.getDataSourceDisplayString(for: viewModel.todaySteps))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "figure.walk")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var realtimeStepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Realtime Steps")
                    .font(.headline)
                Spacer()
                Button(viewModel.isRealtimeUpdating ? "Stop" : "Start") {
                    if viewModel.isRealtimeUpdating {
                        viewModel.stopRealtimeUpdates()
                    } else {
                        viewModel.startRealtimeUpdates()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(viewModel.getStepCountDisplayString(for: viewModel.realtimeSteps))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Data Source: \(viewModel.getDataSourceDisplayString(for: viewModel.realtimeSteps))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if viewModel.isRealtimeUpdating {
                            Text("Updating...")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var weeklyStepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps in the Past 7 Days")
                .font(.headline)
            
            VStack(spacing: 4) {
                ForEach(viewModel.getWeeklyStepsArray(), id: \.date) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.date, format: Date.FormatStyle(date: .numeric, time: .omitted))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(viewModel.getDataSourceDisplayString(for: item.stepData))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(viewModel.getStepCountDisplayString(for: item.stepData))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button("Request Permission Again") {
                Task {
                    await viewModel.requestPermissions()
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.permissionStatus == .requesting)
            
            Button("Refresh Data") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
    }
    
    private var permissionIcon: String {
        switch viewModel.permissionStatus {
        case .notRequested, .requesting:
            return "questionmark.circle"
        case .granted:
            return "checkmark.circle"
        case .denied:
            return "xmark.circle"
        }
    }
    
    private var permissionColor: Color {
        switch viewModel.permissionStatus {
        case .notRequested, .requesting:
            return .orange
        case .granted:
            return .green
        case .denied:
            return .red
        }
    }
    
    private var permissionText: String {
        switch viewModel.permissionStatus {
        case .notRequested:
            return "Not Requested"
        case .requesting:
            return "Requesting..."
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }
    
    private var healthKitAuthStatusText: String {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return "Type Error"
        }
        let healthStore = HKHealthStore()
        let status = healthStore.authorizationStatus(for: stepCountType)
        
        switch status {
        case .notDetermined:
            return "Not Determined"
        case .sharingDenied:
            return "Denied"
        case .sharingAuthorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var specificDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Specific Date Steps")
                .font(.headline)
            
            VStack(spacing: 8) {
                DatePicker("Select Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                
                Button("Fetch Steps") {
                    Task {
                        await viewModel.fetchStepsForSelectedDate()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                
                if let selectedDateSteps = viewModel.selectedDateSteps {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.getStepCountDisplayString(for: selectedDateSteps))")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Data Source: \(viewModel.getDataSourceDisplayString(for: selectedDateSteps))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var monthlyStepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Steps")
                .font(.headline)
            
            VStack(spacing: 8) {
                DatePicker("Select Month", selection: $viewModel.selectedMonth, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                
                Button("Fetch Monthly Steps") {
                    Task {
                        await viewModel.fetchMonthlySteps()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                
                if !viewModel.monthlySteps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.getMonthlyStepsArray().prefix(10), id: \.date) { item in
                                VStack {
                                    Text("\(Calendar.current.component(.day, from: item.date))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text("\(item.stepData.steps)")
                                        .font(.caption2)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color.cyan.opacity(0.2))
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding()
            .background(Color.cyan.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date Range Steps")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Start Date")
                            .font(.caption)
                        DatePicker("", selection: $viewModel.startDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                    VStack(alignment: .leading) {
                        Text("End Date")
                            .font(.caption)
                        DatePicker("", selection: $viewModel.endDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                }
                
                Button("Fetch Range Steps") {
                    Task {
                        await viewModel.fetchDateRangeSteps()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                
                if !viewModel.dateRangeSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total: \(viewModel.getTotalStepsInRange()) steps")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Avg: \(viewModel.getAverageStepsInRange()) steps/day")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("Days: \(viewModel.dateRangeSteps.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.pink.opacity(0.1))
            .cornerRadius(10)
        }
    }
}

#Preview {
    ContentView()
}
