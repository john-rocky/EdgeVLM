//
// ExtractionMode.swift
// EdgeVLM
//

import Foundation

enum ExtractionMode: String, CaseIterable {
    case receipt = "Receipt"
    case businessCard = "Business Card"
    case table = "Table"
    case custom = "Custom"

    var prompt: String {
        switch self {
        case .receipt:
            return "Extract data from this receipt. Output as JSON with fields: store_name, date, items (array of {name, price}), subtotal, tax, total."
        case .businessCard:
            return "Extract data from this business card. Output as JSON with fields: name, title, company, phone, email, address."
        case .table:
            return "Extract the table from this image. Output as CSV format with headers."
        case .custom:
            return ""
        }
    }
}

enum OutputFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
    case plainText = "Text"
}
