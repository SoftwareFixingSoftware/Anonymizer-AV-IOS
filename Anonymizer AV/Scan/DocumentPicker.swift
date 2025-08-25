//
//  DocumentPicker.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 20/08/2025.
//

//
//  DocumentPicker.swift
//  Anonymizer AV
//
//  SwiftUI wrapper around UIDocumentPickerViewController
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Allow multiple selection of any file type
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        controller.allowsMultipleSelection = true
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // no dynamic updates needed
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Do nothing if cancelled
        }
    }
}
