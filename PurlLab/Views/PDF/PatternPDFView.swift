import SwiftUI
import PDFKit

enum PDFZoomTrigger {
    case zoomIn
    case zoomOut
    case reset
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let pdfData: Data
    @Binding var currentPage: Int
    @Binding var zoomTrigger: PDFZoomTrigger?
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.minScaleFactor = 0.4
        pdfView.maxScaleFactor = 5.0
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)
        
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
        // Gestione cambio pagina
        if let document = uiView.document,
           currentPage > 0,
           currentPage <= document.pageCount {
            if let targetPage = document.page(at: currentPage - 1),
               uiView.currentPage != targetPage {
                uiView.go(to: targetPage)
            }
        }
        
        // Gestione Zoom da pulsanti
        if let trigger = zoomTrigger {
            switch trigger {
            case .zoomIn:
                uiView.scaleFactor = min(uiView.scaleFactor * 1.3, uiView.maxScaleFactor)
            case .zoomOut:
                uiView.scaleFactor = max(uiView.scaleFactor / 1.3, uiView.minScaleFactor)
            case .reset:
                uiView.autoScales = true
            }
            DispatchQueue.main.async {
                self.zoomTrigger = nil
            }
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
            super.init()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
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
    @State private var zoomTrigger: PDFZoomTrigger? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Vista PDF nativa con pinch-to-zoom e scala libera
                PDFKitRepresentedView(
                    pdfData: pdfData,
                    currentPage: $currentPage,
                    zoomTrigger: $zoomTrigger
                )
                .edgesIgnoringSafeArea(.bottom)
                
                // Evidenziatore di riga trascinabile
                if isSliderVisible {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.yellow.opacity(0.35))
                            .frame(height: 38)
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(.orange),
                                alignment: .bottom
                            )
                        
                        // Maniglia di trascinamento
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
                
                // Controlli Flottanti per Zoom e Adattamento (in basso a destra)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            // Toggle Evidenziatore
                            Button {
                                withAnimation { isSliderVisible.toggle() }
                            } label: {
                                Image(systemName: isSliderVisible ? "highlighter" : "highlighter")
                                    .symbolVariant(isSliderVisible ? .fill : .none)
                                    .font(.title3.bold())
                                    .foregroundColor(isSliderVisible ? .accentColor : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                            }
                            
                            // Zoom In (+)
                            Button {
                                zoomTrigger = .zoomIn
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.title3.bold())
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                            }
                            
                            // Zoom Out (-)
                            Button {
                                zoomTrigger = .zoomOut
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.title3.bold())
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                            }
                            
                            // Adatta alla larghezza (Reset Zoom)
                            Button {
                                zoomTrigger = .reset
                            } label: {
                                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }
}
