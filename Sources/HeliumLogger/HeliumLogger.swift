/**
 * Copyright IBM Corporation 2015, 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import LoggerAPI
import Foundation

/// The set of colors used when logging with colorized lines.
public enum TerminalColor: String {
    /// Log text in white.
    case white = "\u{001B}[0;37m" // white
    /// Log text in red, used for error messages.
    case red = "\u{001B}[0;31m" // red
    /// Log text in yellow, used for warning messages.
    case yellow = "\u{001B}[0;33m" // yellow
    /// Log text in grey, used for debug messages.
    case grey = "\u{001B}[0;30;1m" // grey
    /// Log text in the terminal's default foreground color.
    case foreground = "\u{001B}[0;39m" // default foreground color
    /// Log text in the terminal's default background color.
    case background = "\u{001B}[0;49m" // default background color
}

/// The set of substitution "variables" that can be used when formatting the
/// messages to be logged.
public enum HeliumLoggerFormatValues: String {
    /// The message being logged.
    case message = "(%msg)"
    /// The name of the function invoking the logger API.
    case function = "(%func)"
    /// The line in the source code of the function invoking the logger API.
    case line = "(%line)"
    /// The file containing the source code of the function invoking the logger API.
    case file = "(%file)"
    /// The type of the logged message (i.e. error, warning, etc.).
    case logType = "(%type)"
    /// The time and date at which the message was logged.
    case date = "(%date)"

    static let all: [HeliumLoggerFormatValues] = [
        .message, .function, .line, .file, .logType, .date
    ]
}

/// The additional set of substitution "variables" that can be used when formatting the
/// messages to be logged with SwiftLog.
public enum HeliumLoggerSwiftLogFormatValues: String {
    /// The logging metadata used by SwiftLog.
    case metadata = "(%metadata)"
    /// The label of the logger used by SwiftLog.
    case label = "(%label)"

    static let all: [HeliumLoggerSwiftLogFormatValues] = [
        .metadata, .label
    ]
}

/// A lightweight implementation of the `LoggerAPI` protocol.
public class HeliumLogger {

    /// A Boolean value that indicates whether the logger output should be colorized.
    ///
    ///### Usage Example: ###
    /// The logger is set up to log `verbose` level messages (this is the default) and all levels below,
    /// that is, it will show messages of type `verbose`, `info`, `warning` and `error`.
    ///```swift
    ///let logger = HeliumLogger()
    ///logger.colored = true
    ///Log.logger = logger
    ///Log.error("This message will be red when your application is run in the terminal.")
    ///```
    public var colored: Bool = false

    /// A Boolean value indicating whether to use the detailed logging format when a user logging format is not
    /// specified.
    public var details: Bool = true

    /// A Boolean value indicating whether to include SwiftLog metadata in the logging format when a user
    /// logging format is not specified.
    public var includeMetadata: Bool = true

    /// A Boolean value indicating whether to include SwiftLog label in the logging format when a user
    /// logging format is not specified.
    public var includeLabel: Bool = true

    /// A Boolean value indicating whether to use the full file path, or just the filename.
    public var fullFilePath: Bool = false

    /// The user specified logging format, if `format` is not `nil`.
    ///
    /// For example: "[(%date)] [(%label)] [(%type)] [(%file):(%line) (%func)] (%msg)".
    public var format: String? {
        didSet {
            if let format = self.format {
                customFormatter = HeliumLogger.parseFormat(format)
            } else {
                customFormatter = nil
            }
        }
    }

    /// The format used when adding the date and time to logged messages, if `dateFormat` is not `nil`.
    public var dateFormat: String? {
        didSet {
            dateFormatter = HeliumLogger.getDateFormatter(format: dateFormat, timeZone: timeZone)
        }
    }

    /// The timezone used in the date time format, if `timeZone` is not `nil`.
    public var timeZone: TimeZone? {
        didSet {
            dateFormatter = HeliumLogger.getDateFormatter(format: dateFormat, timeZone: timeZone)
        }
    }

    /// Default date format - ISO 8601.
    public static let defaultDateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"

    fileprivate var dateFormatter: DateFormatter = HeliumLogger.getDateFormatter()

    static func getDateFormatter(format: String? = nil, timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()

        if let dateFormat = format {
            formatter.dateFormat = dateFormat
        } else {
            formatter.dateFormat = defaultDateFormat
        }

        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }

        return formatter
    }

    #if os(Linux) && !swift(>=3.1)
    typealias NSRegularExpression = RegularExpression
    #endif

    private static var tokenRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: "\\(%\\w+\\)", options: [])
        } catch {
            print("Error creating HeliumLogger tokenRegex: \(error)")
            return nil
        }
    }()

    fileprivate var customFormatter: [LogSegment]?

    enum LogSegment: Equatable {
        case token(HeliumLoggerFormatValues)
        case swiftLogToken(HeliumLoggerSwiftLogFormatValues)
        case literal(String)

        static func == (lhs: LogSegment, rhs: LogSegment) -> Bool {
            switch (lhs, rhs) {
            case (.token(let lhsToken), .token(let rhsToken)) where lhsToken == rhsToken:
                return true
            case (.swiftLogToken(let lhsToken), .swiftLogToken(let rhsToken)) where lhsToken == rhsToken:
                return true
            case (.literal(let lhsLiteral), .literal(let rhsLiteral)) where lhsLiteral == rhsLiteral:
                return true
            default:
                return false
            }
        }
    }

    static func parseFormat(_ format: String) -> [LogSegment] {
        var logSegments = [LogSegment]()

        let nsFormat = NSString(string: format)
        let matches = tokenRegex!.matches(in: format, options: [], range: NSMakeRange(0, nsFormat.length))

        guard !matches.isEmpty else {
            // entire format is a literal, probably a typo in the format
            logSegments.append(LogSegment.literal(format))
            return logSegments
        }

        var loc = 0
        for (index, match) in matches.enumerated() {
            // possible literal segment before token match
            if loc < match.range.location {
                let segment = nsFormat.substring(with: NSMakeRange(loc, match.range.location - loc))
                if !segment.isEmpty {
                    logSegments.append(LogSegment.literal(segment))
                }
            }

            // token regex match, may not be a valid formatValue
            let segment = nsFormat.substring(with: match.range)
            loc = match.range.location + match.range.length
            if let formatValue = HeliumLoggerFormatValues(rawValue: segment) {
                logSegments.append(LogSegment.token(formatValue))
            } else if let swiftLogFormatValue = HeliumLoggerSwiftLogFormatValues(rawValue: segment) {
                logSegments.append(LogSegment.swiftLogToken(swiftLogFormatValue))
            } else {
                logSegments.append(LogSegment.literal(segment))
            }

            // possible literal segment after LAST token match
            let nextIndex = index + 1
            if nextIndex >= matches.count {
                let segment = nsFormat.substring(from: loc)
                if !segment.isEmpty {
                    logSegments.append(LogSegment.literal(segment))
                }
            }
        }

        return logSegments
    }

    /// Create a `HeliumLogger` instance and set it up as the logger used by the `LoggerAPI`
    /// protocol.
    ///
    ///### Usage Example: ###
    /// In the default case, the logger is set up to log `verbose` level messages and all levels below,
    /// that is, it will show messages of type `verbose`, `info`, `warning` and `error`.
    ///```swift
    ///HeliumLogger.use()
    ///```
    /// In the following example, the logger is set up to log `warning` level messages and all levels below, i.e.
    /// it will show messages of type `warning` and `error`.
    ///```swift
    ///HeliumLogger.use(.warning)
    ///```
    /// - Parameter type: The most detailed message type (`LoggerMessageType`) to see in the
    ///                  output of the logger. Defaults to `verbose`.
    public class func use(_ type: LoggerMessageType = .verbose) {
        Log.logger = HeliumLogger(type)
        setbuf(stdout, nil)
    }

    fileprivate let type: LoggerMessageType

    /// Create a `HeliumLogger` instance.
    ///
    /// - Parameter type: The most detailed message type (`LoggerMessageType`) to see in the
    ///                  output of the logger. Defaults to `verbose`.
    public init (_ type: LoggerMessageType = .verbose) {
        self.type = type
    }

    func doPrint(_ message: String) {
        print(message)
    }
}

/// Implement the `LoggerAPI` protocol in the `HeliumLogger` class.
extension HeliumLogger : Logger {

    /// Output a logged message.
    ///
    /// - Parameter type: The type of the message (`LoggerMessageType`) being logged.
    /// - Parameter msg: The message to be logged.
    /// - Parameter functionName: The name of the function invoking the logger API.
    /// - Parameter lineNum: The line in the source code of the function invoking the
    ///                     logger API.
    /// - Parameter fileName: The file containing the source code of the function invoking the
    ///                      logger API.
    public func log(_ type: LoggerMessageType, msg: String,
                    functionName: String, lineNum: Int, fileName: String ) {

        guard isLogging(type) else {
            return
        }

        let message = formatEntry(type: type, msg: msg, functionName: functionName, lineNum: lineNum, fileName: fileName)
        doPrint(message)
    }

    func formatEntry(type: LoggerMessageType, msg: String,
                     functionName: String, lineNum: Int, fileName: String) -> String {
        return formatEntry(type: "\(type)", label: nil, msg: msg, metadata: nil, color: type.color,
                           functionName: functionName, lineNum: lineNum, fileName: fileName)
    }

    func formatEntry(type: String, label: String?, msg: String, metadata: String?, color: TerminalColor,
                     functionName: String, lineNum: Int, fileName: String) -> String {

        let message: String
        if let formatter = customFormatter {
            var line = ""
            for logSegment in formatter {
                let value: String

                switch logSegment {
                case .literal(let literal):
                    value = literal
                case .token(let token):
                    switch token {
                    case .date:
                        value = formatDate()
                    case .logType:
                        value = type
                    case .file:
                        value = getFile(fileName)
                    case .line:
                        value = "\(lineNum)"
                    case .function:
                        value = functionName
                    case .message:
                        value = msg
                    }
                case .swiftLogToken(let token):
                    switch token {
                    case .metadata:
                        value = metadata ?? ""
                    case .label:
                        value = label ?? ""
                    }
                }

                line.append(value)
            }
            message = line
        } else {
            var segments = [String]()

            segments.append("[\(formatDate())]")

            if includeLabel, let label = label {
                segments.append("[\(label)]")
            }

            segments.append("[\(type)]")

            if includeMetadata, let metadata = metadata {
                segments.append("[\(metadata)]")
            }

            if details {
                segments.append("[\(getFile(fileName)):\(lineNum) \(functionName)]")
            }

            segments.append(msg)

            message = segments.joined(separator: " ")
        }

        guard colored else {
            return message
        }

        return color.rawValue + message + TerminalColor.foreground.rawValue
    }

    func formatDate(_ date: Date = Date()) -> String {
        return dateFormatter.string(from: date)
    }

    func getFile(_ path: String) -> String {
        if self.fullFilePath {
            return path
        }
        guard let range = path.range(of: "/", options: .backwards) else {
            return path
        }

        #if swift(>=3.2)
            return String(path[range.upperBound...])
        #else
            return path.substring(from: range.upperBound)
        #endif
    }

    /// Indicates if a message with a specified type (`LoggerMessageType`) will be in the logger
    /// output (i.e. will not be filtered out).
    ///
    ///### Usage Example: ###
    /// The logger is set up to log `warning` level messages and all levels below, that is, it will
    /// show messages of type `warning` and `error`. This means a `verbose` level message will not be displayed.
    ///```swift
    ///let logger = HeliumLogger(.warning)
    ///Log.logger = logger
    ///logger.isLogging(.warning) // Returns true
    ///logger.isLogging(.verbose) // Returns false
    ///```
    /// - Parameter type: The type of message (`LoggerMessageType`).
    ///
    /// - Returns: A Boolean indicating whether a message of the specified type
    ///           (`LoggerMessageType`) will be in the logger output.
    public func isLogging(_ type: LoggerMessageType) -> Bool {
        return type.rawValue >= self.type.rawValue
    }
}

extension LoggerMessageType {
    var color: TerminalColor {
        switch self {
        case .warning:
            return .yellow
        case .error:
            return .red
        case .debug:
            return .grey
        default:
            return .foreground
        }
    }
}
