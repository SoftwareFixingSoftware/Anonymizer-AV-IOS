//
//  Feature.swift
//  Anonymizer AV
//
//  Model representing a single dashboard feature (carousel item).
//

import Foundation

struct Feature: Identifiable, Hashable {
    let id = UUID()
    let iconName: String // SF Symbol or asset name
    let title: String
    let description: String
}
