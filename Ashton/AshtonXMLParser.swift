//
//  XMLParser.swift
//  Ashton
//
//  Created by Michael Schwarz on 15.01.18.
//  Copyright © 2018 Michael Schwarz. All rights reserved.
//

import Foundation


protocol AshtonXMLParserDelegate: class {
    func didParseContent(_ string: String)
    func didOpenTag(_ tag: AshtonXMLParser.Tag, attributes: [AshtonXMLParser.Attribute: [AshtonXMLParser.AttributeKey: String]]?)
    func didCloseTag()
}


final class AshtonXMLParser {
    
    enum Attribute {
        case style
        case href
    }
    
    enum Tag {
        case p
        case span
        case a
        case ignored
    }

    typealias AttributeKey = String
    struct AttributeKeys {

        struct Style {
            static let backgroundColor = "background-color"
            static let color = "color"
            static let textDecoration = "text-decoration"
            static let font = "font"
            static let textAlign = "text-align"
            static let verticalAlign = "vertical-align"

            struct Cocoa {
                static let commonPrefix = "-cocoa-"
                static let strikethroughColor = "strikethrough-color"
                static let underlineColor = "underline-color"
                static let baseOffset = "baseline-offset"
                static let verticalAlign = "vertical-align"
                static let fontPostScriptName = "font-postscriptname"
                static let underline = "underline"
                static let strikethrough = "strikethrough"
            }
        }
    }
    
    private static let closeChar: UnicodeScalar = ">"
    private static let openChar: UnicodeScalar = "<"
    private static let escapeStart: UnicodeScalar = "&"
    
    private let xmlString: String
    
    // MARK: - Lifecycle
    
    weak var delegate: AshtonXMLParserDelegate?
    
    init(xmlString: String) {
        self.xmlString = xmlString
    }
    
    func parse() {
        var parsedScalars = "".unicodeScalars
        var iterator: String.UnicodeScalarView.Iterator = self.xmlString.unicodeScalars.makeIterator()
        
        func flushContent() {
            guard parsedScalars.isEmpty == false else { return }
            
            delegate?.didParseContent(String(parsedScalars))
            parsedScalars = "".unicodeScalars
        }
        
        while let character = iterator.next() {
            switch character {
            case AshtonXMLParser.openChar:
                flushContent()
                self.parseTag(&iterator)
            case AshtonXMLParser.escapeStart:
                let (iteratorAfterEscape, parsedChar)  = self.parseEscape(iterator)
                parsedScalars.append(parsedChar)
                iterator = iteratorAfterEscape
            default:
                parsedScalars.append(character)
            }
        }
        flushContent()
    }
    
    // MARK: - Private
    
    private func parseEscape(_ iterator: String.UnicodeScalarView.Iterator) -> (String.UnicodeScalarView.Iterator, UnicodeScalar) {
        var escapeParseIterator = iterator
        var escapedName = "".unicodeScalars
        
        var parsedCharacters = 0
        while let character = escapeParseIterator.next() {
            if character == ";" {
                switch String(escapedName) {
                case "amp":
                    return (escapeParseIterator, "&")
                case "quot":
                    return (escapeParseIterator, "\"")
                case "apos":
                    return (escapeParseIterator, "'")
                case "lt":
                    return (escapeParseIterator, "<")
                case "gt":
                    return (escapeParseIterator, ">")
                default:
                    return (iterator, "&")
                }
            }
            escapedName.append(character)
            parsedCharacters += 1
            if parsedCharacters > 5 { break }
        }
        return (iterator, "&")
    }
    
    func parseTag(_ iterator: inout String.UnicodeScalarView.Iterator) {
        var potentialTags: Set<Tag> = Set()

        func forwardUntilCloseTag() {
            while let char = iterator.next(), char != ">" {}
        }
        
        switch iterator.next() ?? ">" {
        case "p":
            potentialTags.insert(.p)
        case "s":
            potentialTags.insert(.span)
        case "a":
            potentialTags.insert(.a)
        case ">":
            return
        case "/":
            forwardUntilCloseTag()
            self.delegate?.didCloseTag()
            return
        default:
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        }
        
        switch iterator.next() ?? ">" {
        case " ":
            if potentialTags.contains(.p) {
                let attributes = self.parseAttributes(&iterator)
                self.delegate?.didOpenTag(.p, attributes: attributes)
            } else if potentialTags.contains(.a) {
                let attributes = self.parseAttributes(&iterator)
                self.delegate?.didOpenTag(.a, attributes: attributes)
            } else {
                forwardUntilCloseTag()
                self.delegate?.didOpenTag(.ignored, attributes: nil)
            }
            return
        case "p":
            potentialTags.formIntersection([.span])
        case ">":
            if potentialTags.contains(.p) {
                self.delegate?.didOpenTag(.p, attributes: nil)
            } else if potentialTags.contains(.a) {
                self.delegate?.didOpenTag(.a, attributes: nil)
            } else {
                self.delegate?.didOpenTag(.ignored, attributes: nil)
            }
            return
        default:
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        }
        
        switch iterator.next() ?? ">" {
        case " ", ">":
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        case "a":
            potentialTags.formIntersection([.span])
        default:
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        }
        
        switch iterator.next() ?? ">" {
        case " ", ">":
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        case "n":
            potentialTags.formIntersection([.span])
        default:
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        }
        
        switch iterator.next() ?? ">" {
        case " ":
            if potentialTags.contains(.span) {
                let attributes = self.parseAttributes(&iterator)
                self.delegate?.didOpenTag(.span, attributes: attributes)
            } else {
                forwardUntilCloseTag()
                self.delegate?.didOpenTag(.ignored, attributes: nil)
            }
            return
        case ">":
            if potentialTags.contains(.span) {
                self.delegate?.didOpenTag(.span, attributes: nil)
            } else {
                self.delegate?.didOpenTag(.ignored, attributes: nil)
            }
        default:
            forwardUntilCloseTag()
            self.delegate?.didOpenTag(.ignored, attributes: nil)
            return
        }
    }
    
    func parseAttributes(_ iterator: inout String.UnicodeScalarView.Iterator) -> [Attribute: [AshtonXMLParser.AttributeKey: String]]? {
        var potentialAttributes: Set<Attribute> = Set()
        
        switch iterator.next() ?? ">" {
        case "s":
            potentialAttributes.insert(.style)
        case "h":
            potentialAttributes.insert(.href)
        default:
            return nil
        }
        
        switch iterator.next() ?? ">" {
        case "t":
            guard potentialAttributes.contains(.style) else { return nil }
        case "r":
            guard potentialAttributes.contains(.href) else { return nil }
        default:
            return nil
        }
        
        switch iterator.next() ?? ">" {
        case "y":
            guard potentialAttributes.contains(.style) else { return nil }
        case "e":
            guard potentialAttributes.contains(.href) else { return nil }
        default:
            return nil
        }
        
        switch iterator.next() ?? ">" {
        case "l":
            guard potentialAttributes.contains(.style) else { return nil }
        case "f":
            guard potentialAttributes.contains(.href) else { return nil }
            
            return [.href: self.parseHRef(&iterator)]
        default:
            return nil
        }
        
        switch iterator.next() ?? ">" {
        case "e":
            guard potentialAttributes.contains(.style) else { return nil }
            
            return [.style: self.parseStyles(&iterator)]
        default:
            return nil
        }
    }
    
    func parseStyles(_ iterator: inout String.UnicodeScalarView.Iterator) -> [AttributeKey: String] {
        var attributes: [AttributeKey: String] = [:]

        while let char = iterator.next(), char != ">" {
           iterator.skipStyleAttributeIgnoredCharacters()
            
            guard let firstChar = iterator.testNextCharacter() else { break }
            switch firstChar {
            case "b":
                if iterator.forwardIfEquals(AttributeKeys.Style.backgroundColor) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.backgroundColor] = iterator.scanString(until: ";")
                }
            case "c":
                if iterator.forwardIfEquals(AttributeKeys.Style.color) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.color] = iterator.scanString(until: ";")
                }
            case "t":
                if iterator.forwardIfEquals(AttributeKeys.Style.textAlign) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.textAlign] = iterator.scanString(until: ";")
                } else if iterator.forwardIfEquals(AttributeKeys.Style.textDecoration) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.textDecoration] = iterator.scanString(until: ";")
                }
            case "f":
                if iterator.forwardIfEquals(AttributeKeys.Style.font) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.font] = iterator.scanString(until: ";")
                }
            case "v":
                if iterator.forwardIfEquals(AttributeKeys.Style.verticalAlign) {
                    iterator.skipStyleAttributeIgnoredCharacters()
                    attributes[AttributeKeys.Style.verticalAlign] = iterator.scanString(until: ";")
                }
            case "-":
                if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.commonPrefix) {
                    guard let firstChar = iterator.testNextCharacter() else { break }

                    switch firstChar {
                    case "s":
                        if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.strikethroughColor) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.strikethroughColor] = iterator.scanString(until: ";")
                        } else if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.strikethrough) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.strikethrough] = iterator.scanString(until: ";")
                        }
                    case "u":
                        if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.underlineColor) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.underlineColor] = iterator.scanString(until: ";")
                        } else if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.underline) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.underline] = iterator.scanString(until: ";")
                        }
                    case "b":
                        if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.baseOffset) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.baseOffset] = iterator.scanString(until: ";")
                        }
                    case "v":
                        if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.verticalAlign) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.verticalAlign] = iterator.scanString(until: ";")
                        }
                    case "f":
                        if iterator.forwardIfEquals(AttributeKeys.Style.Cocoa.fontPostScriptName) {
                            iterator.skipStyleAttributeIgnoredCharacters()
                            attributes[AttributeKeys.Style.Cocoa.fontPostScriptName] = iterator.scanString(until: ";")
                        }
                    default:
                        break
                    }
                }
                iterator.forwardIfEquals("-coco")
            default:
                break;
            }
        }
        return attributes
    }
    
    func parseHRef(_ iterator: inout String.UnicodeScalarView.Iterator) -> [AttributeKey: String] {
//        var href = "".unicodeScalars
//
//        while let char = iterator.next(), char != ">" {
//            iterator.skipStyleAttributeIgnoredCharacters()
//        }
        return [:]
    }
}

// MARK: - Private

private extension String.UnicodeScalarView.Iterator {

    @discardableResult
    mutating func forwardIfEquals(_ string: String) -> Bool {
        var testingIterator = self
        var referenceIterator = string.unicodeScalars.makeIterator()
        while let referenceChar = referenceIterator.next() {
            guard referenceChar == testingIterator.next() else { return false }
        }
        self = testingIterator
        return true
    }

    mutating func scanString(until stopChar: Unicode.Scalar) -> String {
        var scannedScalars = "".unicodeScalars
        var scanningIterator = self

        while let char = scanningIterator.next(), char != stopChar {
            self = scanningIterator
            scannedScalars.append(char)
        }
        return String(scannedScalars)
    }

    mutating func skipStyleAttributeIgnoredCharacters() {
        var testingIterator = self
        while let referenceChar = testingIterator.next() {
            switch referenceChar {
            case "=", " ", ";", "\'", ":":
                break
            default:
                return
            }
            self = testingIterator
        }
    }

    func testNextCharacter() -> Unicode.Scalar? {
        var copiedIterator = self
        return copiedIterator.next()
    }
}
