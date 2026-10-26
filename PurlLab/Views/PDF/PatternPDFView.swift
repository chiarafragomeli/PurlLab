import SwiftUI
import PDFKit

struct PDFKitRepresentedView: UIViewRepresentable {
    let pdfData: Data
    @Binding var currentPage: Int
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
        }
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document,
              currentPage > 0,
              currentPage <= document.pageCount else { return }
        
        if let targetPage = document.page(at: currentPage - 1),
           uiView.currentPage != targetPage {
            uiView.go(to: targetPage)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject {
        var parent: PDFKitRepresentedView
        
        init(_ parent: PDFKitRepresentedView) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            let pageIndex = document.index(for: page) + 1
            parent.currentPage = pageIndex
        }
    }
}

struct PatternPDFView: View {
    let pdfData: Data
    @State private var currentPage: Int = 1
    @State private var sliderOffset: CGFloat = 200
    @State private var isSliderVisible: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                PDFKitRepresentedView(pdfData: pdfData, currentPage: $currentPage)
                    .edgesIgnoringSafeArea(.bottom)
                
                // Draggable Slider Highlighter (like knitCompanion)
                if isSliderVisible {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.yellow.opacity(0.35))
                            .frame(height: 36)
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(.orange),
                                alignment: .bottom
                            )
                        
                        // Drag handle
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption2)
                                Text("Evidenziatore")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(radius: 2)
                            .padding(.trailing, 20)
                        }
                    }
                    .offset(y: sliderOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newOffset = sliderOffset + value.translation.height
                                sliderOffset = min(max(newOffset, 0), geometry.size.height - 50)
                            }
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { isSliderVisible.toggle() }
                    } label: {
                        Label("Evidenziatore", systemImage: isSliderVisible ? "highlighter" : "highlighter")
                            .symbolVariant(isSliderVisible ? .fill : .none)
                    }
                }
            }
        }
    }
}
