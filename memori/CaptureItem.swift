//
//  CaptureItem.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//


//
//  CaptureItem.swift
//  Memori
//
//  Created by Abhinav Garapati on 30/08/25.
//


// CaptureItem.swift
import Foundation

struct CaptureItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case photo, video }
    let id: UUID
    let kind: Kind
    let fileURL: URL        // full-size photo or video path
    let thumbURL: URL       // thumbnail jpeg path
    let date: Date
    var note: String?
    var associatedVideoURL: URL?   // optional 3s opposite clip
    var isFavorite: Bool = false
}
