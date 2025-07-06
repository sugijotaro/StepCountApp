import Foundation

/// CoreMotionを使用した歩数データ取得機能を提供するプロトコル
public protocol CoreMotionStepProviding: Sendable {
    /// CoreMotionが利用可能かどうか
    var isAvailable: Bool { get }
    
    /// CoreMotionへのアクセス権限を要求する
    /// - Throws: CoreMotionStepError
    func requestPermission() async throws
    
    /// 今日の歩数を取得する
    /// - Returns: 今日の歩数
    /// - Throws: CoreMotionStepError
    func fetchTodaySteps() async throws -> Int
    
    /// 指定期間の歩数を取得する
    /// - Parameters:
    ///   - startDate: 開始日時
    ///   - endDate: 終了日時
    /// - Returns: 指定期間の歩数
    /// - Throws: CoreMotionStepError
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int
    
    /// 特定の日付の歩数を取得する（直近7日以内のみ）
    /// - Parameter date: 取得する日付
    /// - Returns: 指定日の歩数
    /// - Throws: CoreMotionStepError
    func fetchStepsForSpecificDate(_ date: Date) async throws -> Int
    
    /// リアルタイム歩数更新を開始する
    /// - Parameters:
    ///   - startDate: 更新開始日時
    ///   - handler: 歩数更新時に呼ばれるコールバック
    func startRealtimeStepUpdates(from startDate: Date, handler: @escaping @Sendable (Int) -> Void)
    
    /// リアルタイム歩数更新を停止する
    func stopRealtimeStepUpdates()
}
