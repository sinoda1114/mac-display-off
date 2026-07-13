import Foundation

struct DisplaySleepOption: Identifiable, Equatable {
    let minutes: Int
    let title: String

    var id: Int {
        minutes
    }

    static let all: [DisplaySleepOption] = [
        .init(minutes: 1, title: "1分"),
        .init(minutes: 5, title: "5分"),
        .init(minutes: 10, title: "10分"),
        .init(minutes: 30, title: "30分"),
        .init(minutes: 60, title: "1時間"),
        .init(minutes: 120, title: "2時間"),
        .init(minutes: 0, title: "しない")
    ]

    static func title(for minutes: Int?) -> String {
        guard let minutes else {
            return "取得できません"
        }

        return all.first { $0.minutes == minutes }?.title ?? "\(minutes)分"
    }
}
