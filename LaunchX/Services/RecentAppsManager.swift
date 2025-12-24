import Foundation

/// LRU 最近使用应用管理器
/// 记录用户打开过的应用，按最近使用时间排序
final class RecentAppsManager {
    static let shared = RecentAppsManager()

    private let userDefaultsKey = "recentAppPaths"
    private let maxCapacity = 20  // 最多记录 20 个应用

    /// 获取最近使用的应用路径列表（按 LRU 顺序，最近的在前）
    var recentAppPaths: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    private init() {}

    /// 记录应用被打开（LRU 更新）
    /// - Parameter path: 应用路径
    func recordAppOpen(path: String) {
        var paths = recentAppPaths

        // 如果已存在，先移除（后面会添加到最前面）
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
        }

        // 添加到最前面（最近使用）
        paths.insert(path, at: 0)

        // 超过容量则移除最旧的
        if paths.count > maxCapacity {
            paths = Array(paths.prefix(maxCapacity))
        }

        recentAppPaths = paths
    }

    /// 获取最近使用的应用路径（最多 limit 个）
    /// - Parameter limit: 最大数量
    /// - Returns: 应用路径数组（仅返回实际存在的应用）
    func getRecentApps(limit: Int = 8) -> [String] {
        let paths = recentAppPaths
        var result: [String] = []

        for path in paths {
            guard result.count < limit else { break }
            // 只返回实际存在的应用
            if FileManager.default.fileExists(atPath: path) {
                result.append(path)
            }
        }

        return result
    }

    /// 清空记录
    func clearHistory() {
        recentAppPaths = []
    }
}
