//
//  RWMRuleScheduler.swift
//  RWMRecurrenceRule
//
//  Created by Richard W Maddy on 5/17/18.
//  Copyright © 2018 Maddysoft. All rights reserved.
//

import Foundation

// NOTE - See https://icalendar.org/iCalendar-RFC-5545/3-3-10-recurrence-rule.html

/// The `RWMRuleScheduler` class is used in tadem with `RWMRecurrenceRule` to enumerate and test dates generated by
/// the recurrence rule.
public class RWMRuleScheduler {
    enum Mode {
        case standard
        case eventKit
    }

    var mode: Mode = .standard

    public init() {
    }

    /// Enumerates the dates of the recurrence rule.
    ///
    /// Some more here.
    ///
    /// - Parameters:
    ///   - rule: The recurrence rule.
    ///   - start: The initial `Date` (**DTSTART**) of the recurrence rule.
    ///   - block: A closure that is called for each date generated by the recurrence rule.
    ///   - date: The date.
    ///   - stop: The stop.
    public func enumerateDates(with rule: RWMRecurrenceRule, startingFrom start: Date, using block: (_ date: Date?, _ stop: inout Bool) -> Void) {
        // BYMONTH, BYWEEKNO, BYYEARDAY, BYMONTHDAY, BYDAY, BYHOUR, BYMINUTE, BYSECOND and BYSETPOS

        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = rule.firstDayOfTheWeek?.rawValue ?? 2

        if rule.frequency == .daily {
            // MARK: - DAILY

            // TODO - support BYSETPOS
            var result = start // first result is the start date
            let interval = rule.interval ?? 1
            var count = 0
            var done = false
            var daysOfTheWeek: [Int]? = nil
            if let days = rule.daysOfTheWeek {
                daysOfTheWeek = days.map { $0.dayOfTheWeek.rawValue }
            }

            repeat {
                // Check if we are past the end date or we have returned the desired count
                if let stopDate = rule.recurrenceEnd?.endDate {
                    if result > stopDate {
                        break
                    }
                } else if let stopCount = rule.recurrenceEnd?.count {
                    if count >= stopCount {
                        break
                    }
                }

                // send current result
                var stop = false
                block(result, &stop)
                if (stop) {
                    break
                }

                var attempts = 0
                while attempts < 1000 {
                    attempts += 1
                    // Calculate the next date by adding "interval" days
                    if let date = calendar.date(byAdding: .day, value: interval, to: result) {
                        result = date

                        if let months = rule.monthsOfTheYear {
                            let rmonth = calendar.component(.month, from: result)
                            if !months.contains(rmonth) {
                                continue
                            }
                        }
                        if let monthDays = rule.daysOfTheMonth {
                            var found = false
                            let rday = calendar.component(.day, from: result)
                            for monthDay in monthDays {
                                if monthDay > 0 {
                                    if monthDay == rday {
                                        found = true
                                        break
                                    }
                                } else {
                                    let range = calendar.range(of: .day, in: .month, for: result)!
                                    let lastDay = range.count
                                    if lastDay + monthDay + 1 == rday {
                                        found = true
                                        break
                                    }
                                }
                            }
                            if !found {
                                continue
                            }
                        }
                        if let days = daysOfTheWeek {
                            let rdow = calendar.component(.weekday, from: result)
                            if !days.contains(rdow) {
                                continue
                            }
                        }

                        count += 1
                        break
                    } else {
                        // This shouldn't happen since we should always be able to add x days to the current result
                        done = true
                        break
                    }
                }
            } while !done
        } else if rule.frequency == .weekly {
            // MARK: - WEEKLY

            var result = start // first result is the start date
            let startWeekday = calendar.component(.weekday, from: start)

            var weekdays = [Int]() // 0-6 representing the required week days. 0 is WKST/Calendar.firstWeekday
            let daysOfTheWeek: [Int]
            if let days = rule.daysOfTheWeek {
                daysOfTheWeek = days.map { $0.dayOfTheWeek.rawValue }
            } else {
                daysOfTheWeek = [ startWeekday ]
            }

            var sow: Date
            if mode == .standard {
                let sowcomps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .hour, .minute, .second], from: start)
                sow = calendar.date(from: sowcomps)! // First day of the week containing the start date

                // The rule includes specific weekdays. Based on the rule's WKST (or Calendar.firstWeekday if WKST is 0),
                // we need to convert the chosen BYDAY weekdays into indexes 0 - 6 where 0 is the determined first day of the week.
                // Examples:
                // If WKST is Sunday then index 0=Sun, 1=Mon, 2=Tue, ..., 6=Sat
                // If WKST is Monday then index 0=Mon, 1=Tue, 2=Wed, ..., 6=Sun
                let firstDayOfTheWeek = rule.firstDayOfTheWeek?.rawValue ?? calendar.firstWeekday
                // Convert the standard 1=Sun,2=Mon,...,7=Sat values into the associated weekday index based on the first day of the week
                weekdays = daysOfTheWeek.map { day in
                    let index = (day - firstDayOfTheWeek) % 7
                    return index < 0 ? 7 + index : index
                }
            } else {
                sow = start

                for wd in 0..<7 {
                    if daysOfTheWeek.contains(((startWeekday + wd - 1) % 7) + 1) {
                        weekdays.append(wd)
                    }
                }
            }

            var weekDates = [Date]()
            var dateIndex = 0

            // 7 days per interval
            let interval = (rule.interval ?? 1) * 7
            var count = 0
            var done = false
            repeat {
                if dateIndex < weekDates.count {
                    result = weekDates[dateIndex]
                    dateIndex += 1
                } else {
                    var attempts = 0
                    weekDates = []
                    while weekDates.count == 0 && attempts < 50 {
                        for weekday in weekdays {
                            if let date = calendar.date(byAdding: .day, value: weekday, to: sow) {
                                weekDates.append(date)
                            }
                        }

                        if let months = rule.monthsOfTheYear {
                            weekDates = weekDates.filter {
                                let month = calendar.component(.month, from: $0)
                                return months.contains(month)
                            }
                        }

                        if count == 0 {
                            weekDates = weekDates.filter { $0 > start }
                            weekDates.insert(start, at: 0)
                        }

                        weekDates.sort()
                        if let poss = rule.setPositions {
                            var matches = Set<Date>()
                            for pos in poss {
                                let index = pos > 0 ? pos - 1 : weekDates.count + pos
                                if index >= 0 && index < weekDates.count {
                                    matches.insert(weekDates[index])
                                }
                            }

                            weekDates = matches.sorted()
                        }

                        sow = calendar.date(byAdding: .day, value: interval, to: sow)!
                        attempts += 1
                    }

                    if weekDates.count == 0 {
                        done = true
                        break
                    } else {
                        result = weekDates[0]
                        dateIndex = 1
                    }
                }

                // Check if we are past the end date or we have returned the desired count
                if let stopDate = rule.recurrenceEnd?.endDate {
                    if result > stopDate {
                        done = true
                        break
                    }
                }

                // Send the current result
                var stop = false
                block(result, &stop)
                if (stop) {
                    done = true
                }
                count += 1

                if let stopCount = rule.recurrenceEnd?.count, stopCount > 0 {
                    if count >= stopCount {
                        done = true
                    }
                }
            } while !done
        } else if rule.frequency == .monthly {
            // MARK: - MONTHLY

            var result = start
            var weekdays = [RWMRecurrenceDayOfWeek]()
            var monthDays = [Int]()
            var monthDates = [Date]()
            let monthsOfYear = rule.monthsOfTheYear ?? Array(1...12)
            var dateIndex = 0
            if let daysOfTheMonth = rule.daysOfTheMonth {
                monthDays = daysOfTheMonth
            }
            if let daysOfTheWeek = rule.daysOfTheWeek {
                for dayOfTheWeek in daysOfTheWeek {
                    weekdays.append(dayOfTheWeek)
                }
            }

            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
            comps.day = 1
            var som = calendar.date(from: comps)! // Start of month

            let interval = (rule.interval ?? 1)
            var count = 0

            repeat {
                if weekdays.count > 0 || monthDays.count > 0 {
                    if dateIndex < monthDates.count {
                        result = monthDates[dateIndex]
                        dateIndex += 1
                    } else {
                        var attempts = 0
                        monthDates = []
                        while monthDates.count == 0 && attempts < 100 {
                            var monthComps = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: som)
                            if monthsOfYear.contains(monthComps.month!) {
                                let range = calendar.range(of: .day, in: .month, for: som)!
                                let lastDay = range.count

                                if monthDays.count > 0 {
                                    // First get all the dates for the supplied days of the month
                                    for day in monthDays {
                                        if range.contains(day) {
                                            monthComps.day = day
                                        } else if -day >= 1 && -day < lastDay {
                                            monthComps.day = lastDay + day + 1
                                        } else {
                                            continue
                                        }

                                        if let date = calendar.date(from: monthComps) {
                                            if calendar.date(date, matchesComponents: monthComps) {
                                                monthDates.append(date)
                                            }
                                        }
                                    }

                                    // If specific days of the week have been provided, filter out the dates that don't match
                                    if weekdays.count > 0 {
                                        let wds: [Int] = weekdays.compactMap { $0.weekNumber == 0 ? $0.dayOfTheWeek.rawValue : nil }
                                        let mds: [Int] = weekdays.compactMap {
                                            if $0.weekNumber != 0 {
                                                let comps = DateComponents(year: monthComps.year!, month: monthComps.month!, weekday: $0.dayOfTheWeek.rawValue, weekdayOrdinal: $0.weekNumber)
                                                let date = calendar.date(from: comps)!
                                                return calendar.component(.day, from: date)
                                            } else {
                                                return nil
                                            }
                                        }
                                        monthDates = monthDates.filter {
                                            let wcomps = calendar.dateComponents([ .weekday, .day ], from: $0)
                                            if wds.contains(wcomps.weekday!) {
                                                return true
                                            }
                                            if mds.contains(wcomps.day!) {
                                                return true
                                            }
                                            return false
                                        }
                                    }
                                } else {
                                    // Just specific weekdays
                                    var partialComps = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: som)
                                    for weekday in weekdays {
                                        let weekdayStart: Int
                                        let weekdayEnd: Int
                                        if weekday.weekNumber == 0 {
                                            weekdayStart = 1
                                            weekdayEnd = 5
                                        } else {
                                            weekdayStart = weekday.weekNumber
                                            weekdayEnd = weekdayStart
                                        }

                                        partialComps.weekday = weekday.dayOfTheWeek.rawValue
                                        for wd in stride(from: weekdayStart, through: weekdayEnd, by: 1) {
                                            partialComps.weekdayOrdinal = wd

                                            if let date = calendar.date(from: partialComps) {
                                                if calendar.date(date, matchesComponents: monthComps) {
                                                    monthDates.append(date)
                                                }
                                            }
                                        }
                                    }
                                }

                                monthDates.sort()
                                if let poss = rule.setPositions {
                                    var matches = [Date]()
                                    for pos in poss {
                                        let index = pos > 0 ? pos - 1 : monthDates.count + pos
                                        if index >= 0 && index < monthDates.count {
                                            matches.append(monthDates[index])
                                        }
                                    }

                                    monthDates = matches.sorted()
                                }

                                if count == 0 {
                                    monthDates = monthDates.filter { $0 > start }
                                    monthDates.insert(start, at: 0)
                                    monthDates.sort()
                                }
                            }

                            som = calendar.date(byAdding: .month, value: interval, to: som)!
                            attempts += 1
                        }

                        if monthDates.count == 0 {
                            break
                        } else {
                            result = monthDates[0]
                            dateIndex = 1
                        }
                    }
                } else if count > 0 {
                    var found = false
                    var base = result
                    var tries = 0
                    while !found && tries < 12 {
                        tries += 1
                        if let date = calendar.date(byAdding: .month, value: interval, to: base) {
                            let m = calendar.component(.month, from: date)
                            if monthsOfYear.contains(m) {
                                result = date
                                found = true
                            } else {
                                base = date
                            }
                        } else {
                            break
                        }
                    }
                    if !found {
                        break
                    }
                }

                // Check if we are past the end date or we have returned the desired count
                if let stopDate = rule.recurrenceEnd?.endDate {
                    if result > stopDate {
                        break
                    }
                }

                // Send the current result
                var stop = false
                block(result, &stop)
                if (stop) {
                    break
                }
                count += 1

                if let stopCount = rule.recurrenceEnd?.count, stopCount > 0 {
                    if count >= stopCount {
                        break
                    }
                }
            } while true
        } else if rule.frequency == .yearly {
            // MARK: - YEARLY

            var result = start
            var yearDates = [Date]()
            var dateIndex = 0

            let startComps = calendar.dateComponents([ .year, .month, .day ], from: start)
            let startDay = startComps.day!
            var year = startComps.year!

            let interval = (rule.interval ?? 1)
            var count = 0

            var daysOfTheMonth = rule.daysOfTheMonth
            var monthsOfTheYear = rule.monthsOfTheYear

            if rule.daysOfTheMonth == nil && rule.daysOfTheWeek == nil && rule.daysOfTheYear == nil && rule.monthsOfTheYear == nil && rule.weeksOfTheYear == nil {
                daysOfTheMonth = [ startDay ]
                monthsOfTheYear = [ startComps.month! ]
            }

            repeat {
                if dateIndex < yearDates.count {
                    result = yearDates[dateIndex]
                    dateIndex += 1
                } else {
                    var attempts = 0
                    yearDates = []
                    while yearDates.count == 0 && attempts < 50 {
                        var yearComps = calendar.dateComponents([.year, .hour, .minute, .second], from: start)
                        yearComps.year = year
                        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: yearComps.hour!, minute: yearComps.minute!, second: yearComps.second!))!

                        if let weekNos = rule.weeksOfTheYear {
                            let lastDayOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
                            let lastWeek = calendar.component(.weekOfYear, from: lastDayOfYear)
                            let weeksRange = calendar.range(of: .weekOfYear, in: .yearForWeekOfYear, for: startOfYear)!
                            let weeksInYear = lastWeek == 1 ? CountableRange(weeksRange).last! : lastWeek
                            var weekComps = DateComponents(/*year: year, */hour: yearComps.hour!, minute: yearComps.minute!, second: yearComps.second!, yearForWeekOfYear: year)
                            weekComps.weekday = rule.firstDayOfTheWeek?.rawValue ?? calendar.firstWeekday
                            for weekNo in weekNos {
                                weekComps.weekOfYear = weekNo > 0 ? weekNo : weekNo + 1 + weeksInYear
                                if let startOfWeek = calendar.date(from: weekComps) {
                                    //if let startOfWeek = self.nextDate(after: startOfYear, matching: weekComps, matchingPolicy: .strict) {
                                    if calendar.date(startOfWeek, matchesComponents: yearComps) {
                                        yearDates.append(startOfWeek)
                                        for inc in 1...6 {
                                            if let nextDate = calendar.date(byAdding: .day, value: inc, to: startOfWeek) {
                                                if calendar.date(nextDate, matchesComponents: yearComps) {
                                                    yearDates.append(nextDate)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        var someDatesAdded = yearDates.count > 0

                        if let yearDays = rule.daysOfTheYear {
                            var dayOfYearDates = [Date]()
                            var comps = yearComps
                            for yearDay in yearDays {
                                comps.day = yearDay
                                if let date = calendar.date(fromRelative: comps) {
                                    if calendar.date(date, matchesComponents: yearComps) {
                                        dayOfYearDates.append(date)
                                    }
                                }
                            }
                            if yearDates.count > 0 {
                                yearDates = yearDates.filter { dayOfYearDates.contains($0) }
                            } else {
                                yearDates.append(contentsOf: dayOfYearDates)
                            }

                            someDatesAdded = someDatesAdded || yearDates.count > 0
                        }

                        if let months = monthsOfTheYear ?? (daysOfTheMonth != nil ? Array(1...12) : nil) {
                            if yearDates.count > 0 {
                                // filter existing dates
                                let days: [Int]
                                if let daysOfTheMonth = daysOfTheMonth {
                                    days = daysOfTheMonth
                                //} else if rule.daysOfTheWeek == nil {
                                //    days = [startDay]
                                } else {
                                    days = Array(1...31)
                                }
                                let filtered = yearDates.filter {
                                    let comps = calendar.dateComponents([.month, .day], from: $0)
                                    return months.contains(comps.month!) && days.contains(comps.day!)
                                }
                                yearDates = filtered
                            } else if !someDatesAdded {
                                // create dates for every day of each month
                                for month in months {
                                    var monthComps = yearComps
                                    monthComps.month = month
                                    monthComps.day = 1
                                    if let startOfMonth = calendar.date(from: monthComps) {
                                        let days: [Int]
                                        if let daysOfTheMonth = rule.daysOfTheMonth {
                                            let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
                                            days = daysOfTheMonth.map { $0 > 0 ? $0 : range.count + $0 + 1 }.filter { range.contains($0) }
                                        } else if rule.daysOfTheWeek == nil {
                                            days = [startDay]
                                        } else {
                                            let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
                                            days = Array(CountableRange(range).indices)
                                        }
                                        for day in days {
                                            monthComps.day = day
                                            if let nextDate = calendar.date(from: monthComps) {
                                                yearDates.append(nextDate)
                                            }
                                        }
                                    }
                                }

                                someDatesAdded = someDatesAdded || yearDates.count > 0
                            }
                        }

                        if let daysOfTheWeek = rule.daysOfTheWeek {
                            if yearDates.count > 0 {
                                let filtered = yearDates.filter {
                                    let comps = calendar.dateComponents([.year, .month, .weekday, .weekdayOrdinal ], from: $0)
                                    var numWeeksComps = comps
                                    numWeeksComps.weekdayOrdinal = -1
                                    let lastWeekDate = calendar.date(from: numWeeksComps)!
                                    let numWeeks = calendar.component(.weekdayOrdinal, from: lastWeekDate)
                                    for dayOfTheWeek in daysOfTheWeek {
                                        if dayOfTheWeek.weekNumber == 0 {
                                            if comps.weekday! == dayOfTheWeek.dayOfTheWeek.rawValue {
                                                return true
                                            }
                                        } else {
                                            let weekNo = dayOfTheWeek.weekNumber > 0 ? dayOfTheWeek.weekNumber : dayOfTheWeek.weekNumber + numWeeks + 1
                                            if comps.weekday! == dayOfTheWeek.dayOfTheWeek.rawValue && comps.weekdayOrdinal! == weekNo {
                                                return true
                                            }
                                        }
                                    }

                                    return false
                                }
                                yearDates = filtered
                            } else if !someDatesAdded {
                                var partialComps = calendar.dateComponents([.year, .hour, .minute, .second], from: startOfYear)
                                for weekday in daysOfTheWeek {
                                    let weekdayStart: Int
                                    let weekdayEnd: Int
                                    if weekday.weekNumber == 0 {
                                        weekdayStart = 1
                                        weekdayEnd = 54
                                    } else {
                                        weekdayStart = weekday.weekNumber
                                        weekdayEnd = weekdayStart
                                    }

                                    partialComps.weekday = weekday.dayOfTheWeek.rawValue
                                    for wd in stride(from: weekdayStart, through: weekdayEnd, by: 1) {
                                        var date: Date?
                                        if wd > 0 {
                                            partialComps.weekdayOrdinal = wd
                                            date = calendar.date(from: partialComps)
                                        } else {
                                            var lastComps = partialComps
                                            lastComps.month = 12
                                            lastComps.weekdayOrdinal = -1
                                            let lastDay = calendar.date(from: lastComps)!
                                            date = calendar.date(byAdding: .day, value: (wd + 1) * 7, to: lastDay)
                                        }

                                        if let date = date {
                                            if calendar.date(date, matchesComponents: yearComps) {
                                                yearDates.append(date)
                                            }
                                        }
                                    }
                                }
                            }

                            //someDatesAdded = someDatesAdded || yearDates.count > 0
                        }

                        yearDates.sort()
                        if let poss = rule.setPositions {
                            var matches = [Date]()
                            for pos in poss {
                                let index = pos > 0 ? pos - 1 : yearDates.count + pos
                                if index >= 0 && index < yearDates.count {
                                    matches.append(yearDates[index])
                                }
                            }

                            yearDates = matches.sorted()
                        }

                        if count == 0 {
                            yearDates = yearDates.filter { $0 > start }
                            yearDates.insert(start, at: 0)
                            yearDates.sort()
                        }

                        year += interval
                        attempts += 1
                    }

                    if yearDates.count == 0 {
                        break
                    } else {
                        result = yearDates[0]
                        dateIndex = 1
                    }
                }

                // Check if we are past the end date or we have returned the desired count
                if let stopDate = rule.recurrenceEnd?.endDate {
                    if result > stopDate {
                        break
                    }
                }

                // Send the current result
                var stop = false
                block(result, &stop)
                if (stop) {
                    break
                }
                count += 1

                if let stopCount = rule.recurrenceEnd?.count, stopCount > 0 {
                    if count >= stopCount {
                        break
                    }
                }
            } while true
        }
    }

    /// Determines if the date is one of the dates generated by the recurrence rule.
    ///
    /// - Parameters:
    ///   - date: The date to check for.
    ///   - rule: The recurrence rule generating the list of dates.
    ///   - start: The start date used as the basis of the recurrence rule.
    ///   - exact: `true` if the full date and time must match, `false` if the time is ignored.
    /// - Returns: `true` if `date` is one of the dates generated by `rule`, `false` if not.
    public func includes(date: Date, with rule: RWMRecurrenceRule, startingFrom start: Date, exact: Bool = false) -> Bool {
        var found = false

        enumerateDates(with: rule, startingFrom: start) { (rdate, stop) in
            if let rdate = rdate {
                if (exact && rdate == date) || (!exact && Calendar.current.isDate(rdate, inSameDayAs: date)) {
                    found = true
                    stop = true
                } else if rdate > date {
                    stop = true
                }
            }
        }

        return found
    }

    /// Returns the next possible event date after the supplied date. If there are no recurrences after the date,
    /// the result is `nil`.
    ///
    /// - Parameters:
    ///   - date: The date to check for.
    ///   - rule: The recurrence rule generating the list of dates.
    ///   - start: The start date used as the basis of the recurrence rule.
    /// - Returns: The first date after `date` in the list of dates generated by `rule`. If `date` is after the last recurrence date, the result is `nil`.
    public func nextDate(after date: Date, with rule: RWMRecurrenceRule, startingFrom start: Date) -> Date? {
        var found: Date? = nil

        enumerateDates(with: rule, startingFrom: start) { (rdate, stop) in
            if let rdate = rdate {
                if rdate > date {
                    stop = true
                    found = rdate
                }
            }
        }

        return found
    }
}
