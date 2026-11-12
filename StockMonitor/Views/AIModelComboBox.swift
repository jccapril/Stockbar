// Created by april on 2026/11/12.
import AppKit
import SwiftUI

struct AIModelComboBox: NSViewRepresentable {
    @Binding var selection: String
    let models: [String]

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.completes = false
        comboBox.placeholderString = "选择或输入模型名称"
        comboBox.setAccessibilityLabel("模型名称")
        comboBox.numberOfVisibleItems = 10
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.selection = $selection
        let options = models
        if comboBox.objectValues as? [String] != options {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: options)
        }
        // 只同步外部变更，保留输入过程中的光标和选区。
        if comboBox.stringValue != selection {
            comboBox.stringValue = selection
        }
        comboBox.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            selection.wrappedValue = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  let value = comboBox.objectValueOfSelectedItem as? String else { return }
            selection.wrappedValue = value
        }
    }
}
