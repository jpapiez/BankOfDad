import AVFoundation
import SwiftUI
import UIKit

struct CodeScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (@MainActor (String) -> Void)?
    private let capture = CaptureSessionRunner()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capture.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        capture.stop()
    }

    private func configure() {
        let session = capture.session
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        let label = UILabel()
        label.text = "Point the camera at the Bank of Dad QR code"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = object.stringValue else { return }
        capture.stop()
        if let url = URL(string: value), let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            onCode?(code)
        } else {
            onCode?(value)
        }
    }

    private final class CaptureSessionRunner {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.example.bankofdad.qr-scanner")

        func start() {
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
        }

        func stop() {
            queue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }
    }
}
