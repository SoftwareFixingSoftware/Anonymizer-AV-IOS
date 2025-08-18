//
//  FeatureCard.swift
//  Anonymizer AV
//
//  Reusable carousel item in Quarantine theme style
//

import SwiftUI

struct FeatureCard: View {
    let feature: Feature
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Icon
                if UIImage(systemName: feature.iconName) != nil {
                    Image(systemName: feature.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundColor(.accentCyan)
                } else {
                    Image(feature.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }

                // Title
                Text(feature.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                // Description
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 160, height: 130, alignment: .topLeading)
            // Removed inner background & shadow to adopt Quarantine theme
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureCard_Previews: PreviewProvider {
    static var previews: some View {
        FeatureCard(
            feature: Feature(iconName: "shield.lefthalf.fill",
                             title: "Real-time Protection",
                             description: "Constantly scans")
        ) {
            print("Feature tapped")
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
