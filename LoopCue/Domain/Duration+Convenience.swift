import Foundation

extension Duration {
    /// 便捷构造：N 分钟。
    static func minutes(_ value: Int64) -> Duration {
        .seconds(value * 60)
    }

    /// 便捷构造：N 小时。
    static func hours(_ value: Int64) -> Duration {
        .minutes(value * 60)
    }
}

