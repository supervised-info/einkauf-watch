import UIKit

enum TodoListPDFError: LocalizedError {
    case empty

    var errorDescription: String? {
        "Die Liste ist leer."
    }
}

/// Druckbare To-Do-Liste (iOS). Gruppen nach Person; Aufrufer filtert mit `TodoListGrouping.groups`.
/// Meta-Zeile: `progressLabel` als `oo/xx/yy` (offen/erledigt/gesamt der gedruckten Aufgaben).
/// Checkboxen wie `ListPDF`: leeres Quadrat; `completed` nur Durchstreichen/Farbe.
enum TodoListPDF {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
    private static let margin: CGFloat = 48
    private static let titleFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
    private static let metaFont = UIFont.systemFont(ofSize: 14, weight: .regular)
    private static let headerFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let itemFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    private static let itemMetaFont = UIFont.systemFont(ofSize: 12, weight: .regular)
    private static let checkboxSize: CGFloat = 18
    private static let checkboxGap: CGFloat = 10
    private static let rowSpacing: CGFloat = 8
    private static let sectionSpacing: CGFloat = 16

    static func render(
        groups: [TodoPDFGroup],
        progressLabel: String,
        colors: ThemeRGB,
        today: String = TodoTime.localDayIso()
    ) throws -> Data {
        guard !groups.isEmpty else { throw TodoListPDFError.empty }
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "To-Do Liste",
            kCGPDFContextCreator as String: "Einkauf"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            var painter = Painter(
                context: context,
                paper: uiColor(colors.paper),
                ink: uiColor(colors.ink),
                muted: uiColor(colors.muted),
                rule: uiColor(colors.rule),
                oxide: uiColor(colors.oxide),
                today: today
            )
            painter.draw(groups: groups, progressLabel: progressLabel)
        }
        guard !data.isEmpty else { throw TodoListPDFError.empty }
        return data
    }

    private static func uiColor(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    private struct Painter {
        let context: UIGraphicsPDFRendererContext
        let paper: UIColor
        let ink: UIColor
        let muted: UIColor
        let rule: UIColor
        let oxide: UIColor
        let today: String
        var y: CGFloat = 0

        private var page: CGRect { TodoListPDF.pageRect }
        private var inset: CGFloat { TodoListPDF.margin }
        private var contentWidth: CGFloat { page.width - inset * 2 }
        private var bottom: CGFloat { page.height - inset }
        private var remaining: CGFloat { bottom - y }

        mutating func draw(groups: [TodoPDFGroup], progressLabel: String) {
            beginPage()

            y += drawText("To-Do Liste", font: TodoListPDF.titleFont, color: ink, width: contentWidth) + 6
            y += drawText(progressLabel, font: TodoListPDF.metaFont, color: muted, width: contentWidth) + 10

            let cg = context.cgContext
            cg.setStrokeColor(rule.cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: inset, y: y))
            cg.addLine(to: CGPoint(x: page.width - inset, y: y))
            cg.strokePath()
            y += 16

            let box = TodoListPDF.checkboxSize
            let gap = TodoListPDF.checkboxGap
            let textWidth = contentWidth - box - gap
            for group in groups {
                let header = group.title.uppercased(with: Locale(identifier: "de_DE"))
                let headerH = measure(header, font: TodoListPDF.headerFont, width: contentWidth)
                let rowHeights = group.tasks.map { task in
                    rowHeight(task, box: box, textWidth: textWidth)
                }
                let rowsH = rowHeights.reduce(0) { $0 + $1 + TodoListPDF.rowSpacing }
                let sectionH = headerH + 8 + rowsH
                let minBlock = headerH + 8 + (rowHeights.first ?? 0)
                let pageBody = page.height - inset * 2
                if y > inset + 32 {
                    if sectionH <= pageBody && sectionH > remaining {
                        beginPage()
                    } else if minBlock > remaining {
                        beginPage()
                    }
                }

                ensure(headerH + 8)
                y += drawText(header, font: TodoListPDF.headerFont, color: muted, width: contentWidth) + 8

                for (idx, task) in group.tasks.enumerated() {
                    let rowH = rowHeights[idx]
                    ensure(rowH)
                    let nameH = measure(
                        task.text,
                        font: TodoListPDF.itemFont,
                        width: textWidth,
                        strike: task.completed
                    )
                    drawCheckbox(origin: CGPoint(x: inset, y: y + max(0, (nameH + 4 - box) / 2)))
                    let attrs = itemAttributes(name: task.text, done: task.completed)
                    attrs.draw(in: CGRect(
                        x: inset + box + gap,
                        y: y + 1,
                        width: textWidth,
                        height: nameH + 2
                    ))
                    let meta = TodoListGrouping.metaLine(task)
                    if !meta.isEmpty {
                        let metaY = y + 1 + nameH + 2
                        let metaColor = TodoOrdering.isOverdue(task.dueDate, today: today) ? oxide : muted
                        let metaNS = NSAttributedString(string: meta, attributes: [
                            .font: TodoListPDF.itemMetaFont,
                            .foregroundColor: metaColor
                        ])
                        let metaH = ceil(metaNS.boundingRect(
                            with: CGSize(width: textWidth, height: 10_000),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            context: nil
                        ).height)
                        metaNS.draw(in: CGRect(
                            x: inset + box + gap,
                            y: metaY,
                            width: textWidth,
                            height: metaH
                        ))
                    }
                    y += rowH + TodoListPDF.rowSpacing
                }
                y += TodoListPDF.sectionSpacing - TodoListPDF.rowSpacing
            }
        }

        func rowHeight(_ task: TodoTask, box: CGFloat, textWidth: CGFloat) -> CGFloat {
            let nameH = measure(
                task.text,
                font: TodoListPDF.itemFont,
                width: textWidth,
                strike: task.completed
            )
            let meta = TodoListGrouping.metaLine(task)
            let metaH = meta.isEmpty
                ? 0
                : measure(meta, font: TodoListPDF.itemMetaFont, width: textWidth) + 2
            return max(box, nameH + metaH) + 4
        }

        mutating func beginPage() {
            context.beginPage()
            let cg = context.cgContext
            cg.setFillColor(paper.cgColor)
            cg.fill(page)
            y = inset
        }

        mutating func ensure(_ height: CGFloat) {
            if height > remaining { beginPage() }
        }

        func measure(_ text: String, font: UIFont, width: CGFloat, strike: Bool = false) -> CGFloat {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if strike {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            let ns = NSAttributedString(string: text, attributes: attrs)
            let bounds = ns.boundingRect(
                with: CGSize(width: width, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return ceil(bounds.height)
        }

        @discardableResult
        func drawText(_ text: String, font: UIFont, color: UIColor, width: CGFloat) -> CGFloat {
            let ns = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color
            ])
            let height = ceil(ns.boundingRect(
                with: CGSize(width: width, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height)
            ns.draw(in: CGRect(x: inset, y: y, width: width, height: height))
            return height
        }

        func itemAttributes(name: String, done: Bool) -> NSAttributedString {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: TodoListPDF.itemFont,
                .foregroundColor: done ? muted : ink
            ]
            if done {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = muted
            }
            return NSAttributedString(string: name, attributes: attrs)
        }

        func drawCheckbox(origin: CGPoint) {
            let size = TodoListPDF.checkboxSize
            let box = CGRect(x: origin.x, y: origin.y, width: size, height: size)
                .insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: box, cornerRadius: 2.5)
            muted.setStroke()
            path.lineWidth = 1.75
            path.stroke()
        }
    }
}
