import Foundation
import Cocoa

public struct ParsedOTP {
    let service: String?
    let code: String
    
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

protocol OTPParser {
    func parseMessage(_ message: String) -> ParsedOTP?
}

public class TwoFHeyOTPParser: OTPParser {
    var config: OTPParserConfiguration
    
    init(withConfig config: OTPParserConfiguration) {
        self.config = config
    }
        
    private func isValidCodeInMessageContext(message: String, code: String) -> Bool {
        guard !code.isEmpty, let codePosition = message.index(of: code), let afterCodePosition = message.endIndex(of: code) else { return false }
        
        if codePosition > message.startIndex {
            let prev = message[message.index(before: codePosition)]
            if prev == "-" || prev == "/" || prev == "\\" || prev == "$" {
                return false
            }
        }
        
        if afterCodePosition < message.endIndex {
            let next = message[message.index(after: afterCodePosition)]
            // make sure next character is whitespace or ending grammar
            if !OTPParserConstants.endingCharacters.contains(next) {
                return false
            }
        }
        
        return true
    }
    
    public func parseMessage(_ message: String) -> ParsedOTP? {
        let lowercaseMessage = message.lowercased()
        
        if let googleOTP = OTPParserConstants.googleOTPRegex.firstCaptureGroupInString(message) {
            return ParsedOTP(service: "google", code: googleOTP)
        }
        
        let service = inferServiceFromMessage(message)
        
        if let possibleCode = OTPParserConstants.CodeMatchingRegularExpressions.standardFourToEight.firstCaptureGroupInString(lowercaseMessage) {
            return ParsedOTP(service: service, code: possibleCode)
        }
        
        let standardRegExps: [NSRegularExpression] = [
            OTPParserConstants.CodeMatchingRegularExpressions.standardFourToEight,
            OTPParserConstants.CodeMatchingRegularExpressions.dashedThreeAndThree,
        ]

        for regex in standardRegExps {
            let matches = regex.matchesInString(lowercaseMessage)
            for match in matches {
                guard let code = match.firstCaptureGroupInString(lowercaseMessage) else { continue }

                if isValidCodeInMessageContext(message: lowercaseMessage, code: code) {
                    return ParsedOTP(service: service, code: code)
                }
            }
        }
        
        let matchedParser = CUSTOM_PARSERS.first { parser in
            if let requiredName = parser.requiredServiceName, requiredName != service {
                return false
            }
            
            guard parser.canParseMessage(message), parser.parseMessage(message) != nil else { return false }
            
            return true
        }
        
        if let matchedParser = matchedParser, let parsedCode = matchedParser.parseMessage(message) {
            return parsedCode
        }
        
        return nil
    }
    
    private func inferServiceFromMessage(_ message: String) -> String? {
        let lowercaseMessage = message.lowercased()
        for servicePattern in config.servicePatterns {
            guard let possibleServiceName = servicePattern.firstCaptureGroupInString(lowercaseMessage),
                  !possibleServiceName.isEmpty,
                  !OTPParserConstants.authWords.contains(possibleServiceName) else {
                continue
            }
            
            return possibleServiceName
        }
        
        for knownService in config.knownServices {
            if lowercaseMessage.contains(knownService) {
                return knownService
            }
        }
        
        return nil
    }
}
