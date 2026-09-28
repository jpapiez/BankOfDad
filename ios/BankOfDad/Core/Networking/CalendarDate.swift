import Foundation

struct CalendarDate: Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    init(string: String) throws {
        let pieces = string.split(separator: "-").map(String.init)
        guard pieces.count == 3,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]),
              (1...12).contains(month), (1...31).contains(day) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid calendar date: \(string)"))
        }
        self.init(year: year, month: month, day: day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}
