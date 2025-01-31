//
//  ParmaCore.swift
//  Parma
//
//  Created by leonard on 8/16/20.
//
//  Copyright (c) 2020 Leonard Chan <wxclx98@gmail.com>
//
//  MIT license, see LICENSE file for details

import SwiftUI
import Down

public typealias Text = SwiftUI.Text

@available(iOS 13.0, macOS 10.15, *)
/// The main logic of Parma.
class ParmaCore: NSObject {
    // MARK: - Class property
    
    // Composer collections
    private var inlineComposers: [Element : InlineElementComposer] = [:]
    private var blockComposers: [Element : BlockElementComposer] = [:]
    
    // Composers
    private let plaintTextComposer = PlainTextComposer()
    private let strongElementComposer = StrongElementComposer()
    private let emphasisElementComposer = EmphasisElementComposer()
    private let linkElementComposer = LinkElementComposer()
    private let codeElementComposer = CodeElementComposer()
    private let headingElementComposer = HeadingElementComposer()
    private let paragraphElementComposer = ParagraphElementComposer()
    private let imageElementComposer = ImageElementComposer()
    private let listElementComposer = ListElementComposer()
    private let listItemElementComposer = ListItemElementComposer()
    private let unknownElementComposer = UnknownElementComposer()
    
    private let parser: XMLParser
    
    // Generated views
    private var views: Array<AnyView> = []
    
    // Temporary storage
    private var texts: Array<Text> = []
    private var foundCharacters = ""
    private var concatenatedText: Text {
        return texts.reduce(Text(""), +)
    }
    
    // MARK: - Public property
    var composedView: AnyView {
        AnyView(
            ForEach(0..<views.count, id: \.self) { index in
                self.views[index]
            }
        )
    }
    
    /// The render for views.
    var render: ParmaRenderable = ParmaRender()
    
    /// The context for element composing.
    let context = ComposingContext()
    
    /// Sanitize input to prevent < and > from causing problems
    private static func escapeContent(_ rawContent: String) -> String {
        
        enum EscapedCharacters: String, CaseIterable {
            
            case leftAngleBracket = "<",
                 rightAngleBracket = ">"
            
            func replacement() -> String {
                switch self {
                case .leftAngleBracket:
                    return "&lt;"
                case .rightAngleBracket:
                    return "&gt;"
                }
            }
            
            static func escapeString(_ string: String) -> String {
                var escapedValue = string
                
                self.allCases.forEach {
                    escapedValue = escapedValue.replacingOccurrences(of: $0.rawValue, with: $0.replacement())
                }
                
                return escapedValue
            }
        }
        
        return EscapedCharacters.escapeString(rawContent)
    }
    
    // MARK: - Initialization
    convenience init(_ markdown: String) throws {
        let down = Down(markdownString: Self.escapeContent(markdown))
        let xml = try down.toXML()
        self.init(xmlData: Data(xml.utf8))
    }
    
    /// Create a Parma core.
    /// - Parameter xmlData: The xml data generated by Down.
    init(xmlData: Data) {
        parser = XMLParser(data: xmlData)
        super.init()
        parser.delegate = self
        
        // Register composers
        inlineComposers =
        [
            .text : plaintTextComposer,
            .strong : strongElementComposer,
            .emphasis : emphasisElementComposer,
            .link : linkElementComposer,
            .code : codeElementComposer,
        ]
        blockComposers =
        [
            .paragraph : paragraphElementComposer,
            .heading : headingElementComposer,
            .image : imageElementComposer,
            .list : listElementComposer,
            .item : listItemElementComposer,
            .unknown : unknownElementComposer
        ]
    }
    
    /// Start composing views.
    func start() {
        parser.parse()
    }
}

// MARK: - XML parsing logic
extension ParmaCore: XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Start new element
        let element = Element.element(elementName)
        
        if element != .unknown {
            context.enter(in: element)
        }
        
        context.attributes = attributeDict
        
        if element.isInline {
            inlineComposers[element]?.willStart(in: context)
        } else {
            blockComposers[element]?.willStart(in: context)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = Element.element(elementName)
        
        if element.isInline {
            if let text = inlineComposers[element]?.text(in: context, render: render) {
                if let superEl = context.superElement, superEl.isInline {
                    context.texts = []
                    context.texts.append(text)
                } else {
                    context.texts = []
                    texts.append(text)
                    context.texts = texts
                }
            }

            inlineComposers[element]?.willStop(in: context)
        } else {
            if let text = blockComposers[element]?.text(in: context, render: render) {
                context.views.append(AnyView(text))
            } else {
                if texts.count != 0 {
                    context.views.append(AnyView(concatenatedText))
                }
            }
            
            texts = []
            context.texts = []
            
            if let view = blockComposers[element]?.view(in: context, render: render) {
                if context.stack.count > 1 {
                    context.views.append(view)
                } else {
                    context.views = []
                    views.append(view)
                }
            }
            
            blockComposers[element]?.willStop(in: context)
        }
        
        context.foundCharacters = ""
        
        if element != .unknown {
            context.leaveElement()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard string.trimmingCharacters(in: .whitespacesAndNewlines) != "" else { return }
        context.foundCharacters += string.trimmingCharacters(in: .newlines)
    }
}
