import UIKit
import AVFoundation

/// Protocole pour les événements du scanner
@available(iOS 13.0, *)
protocol CaptureViewControllerDelegate: AnyObject {
    func captureViewController(_ controller: CaptureViewController, didCaptureImage image: UIImage, withDocument document: DocumentDetector.DetectedDocument?)
    func captureViewControllerDidCancel(_ controller: CaptureViewController)
}

/// ViewController pour la capture de documents avec preview caméra
@available(iOS 13.0, *)
class CaptureViewController: UIViewController {

    weak var delegate: CaptureViewControllerDelegate?

    // MARK: - Composants UI

    private lazy var previewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var overlayView: DocumentOverlayView = {
        let view = DocumentOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.cgColor

        // Cercle intérieur
        let innerCircle = UIView()
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 28
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.isUserInteractionEnabled = false
        button.addSubview(innerCircle)

        NSLayoutConstraint.activate([
            innerCircle.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 56),
            innerCircle.heightAnchor.constraint(equalToConstant: 56)
        ])

        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Annuler", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Positionnez le document dans le cadre"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = ""
        label.textColor = .systemGreen
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        return label
    }()

    // MARK: - Capture Session

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.capturehelper.capture", qos: .userInteractive)

    // MARK: - Détection

    private let documentDetector = DocumentDetector()
    private var lastDetectedDocument: DocumentDetector.DetectedDocument?
    private var isCapturing = false

    /// Dimensions du buffer vidéo pour la conversion des coordonnées
    private var videoBufferSize: CGSize = .zero

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCaptureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Réinitialiser l'état de capture quand on revient sur cet écran
        isCapturing = false
        lastDetectedDocument = nil
        overlayView.hideOverlay(animated: false)
        startCapture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(previewView)
        view.addSubview(overlayView)
        view.addSubview(captureButton)
        view.addSubview(cancelButton)
        view.addSubview(instructionLabel)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Preview plein écran
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Overlay par-dessus la preview
            overlayView.topAnchor.constraint(equalTo: previewView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),

            // Bouton de capture en bas au centre
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            // Bouton annuler en bas à gauche
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),

            // Instruction en haut
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            // Status au-dessus du bouton capture
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20)
        ])

        // Padding pour l'instruction
        instructionLabel.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    }

    // MARK: - Capture Session Setup

    private func setupCaptureSession() {
        captureSession.sessionPreset = .photo

        // Configurer l'entrée caméra
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            showError("Impossible d'accéder à la caméra")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Configurer la sortie vidéo pour la détection en temps réel
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Configurer la preview
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = previewView.bounds

        if let previewLayer = previewLayer {
            previewView.layer.addSublayer(previewLayer)
        }

        // Configurer l'autofocus continu
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {
            print("Erreur configuration caméra: \(error)")
        }
    }

    private func startCapture() {
        captureQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func stopCapture() {
        captureQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Actions

    @objc private func captureButtonTapped() {
        guard !isCapturing else { return }
        isCapturing = true

        overlayView.showCaptureFlash()

        // Capturer l'image actuelle
        captureCurrentFrame()
    }

    @objc private func cancelButtonTapped() {
        stopCapture()
        delegate?.captureViewControllerDidCancel(self)
    }

    // MARK: - Capture

    private var lastSampleBuffer: CMSampleBuffer?

    private func captureCurrentFrame() {
        guard let sampleBuffer = lastSampleBuffer,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isCapturing = false
            showError("Impossible de capturer l'image")
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        // Appliquer la rotation correcte
        let rotatedImage = ciImage.oriented(.right)

        guard let cgImage = context.createCGImage(rotatedImage, from: rotatedImage.extent) else {
            isCapturing = false
            showError("Impossible de créer l'image")
            return
        }

        let image = UIImage(cgImage: cgImage)

        stopCapture()

        // Passer au delegate avec le document détecté
        delegate?.captureViewController(self, didCaptureImage: image, withDocument: lastDetectedDocument)
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(
                title: "Erreur",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.delegate?.captureViewControllerDidCancel(self!)
            })
            self?.present(alert, animated: true)
        }
    }

    private func updateStatus(documentDetected: Bool, isStable: Bool) {
        DispatchQueue.main.async { [weak self] in
            if documentDetected {
                if isStable {
                    self?.statusLabel.text = "Document détecté - Prêt"
                    self?.statusLabel.textColor = .systemGreen
                    self?.captureButton.layer.borderColor = UIColor.systemGreen.cgColor
                } else {
                    self?.statusLabel.text = "Stabilisez le document..."
                    self?.statusLabel.textColor = .systemYellow
                    self?.captureButton.layer.borderColor = UIColor.systemYellow.cgColor
                }
            } else {
                self?.statusLabel.text = ""
                self?.captureButton.layer.borderColor = UIColor.white.cgColor
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
@available(iOS 13.0, *)
extension CaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Garder le dernier buffer pour la capture
        lastSampleBuffer = sampleBuffer

        // Récupérer les dimensions du buffer vidéo
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            // Note: le buffer est en mode paysage, donc on inverse pour le mode portrait
            videoBufferSize = CGSize(width: bufferHeight, height: bufferWidth)
        }

        // Ne pas détecter pendant la capture
        guard !isCapturing else { return }

        // Détecter le document
        documentDetector.detectDocument(in: sampleBuffer) { [weak self] document in
            guard let self = self else { return }

            self.lastDetectedDocument = document

            if let document = document {
                // Convertir les points Vision vers les coordonnées de la vue
                let points = self.convertVisionPointsToViewPoints(document: document)
                self.overlayView.updateDocumentBounds(points: points, animated: true)
                self.updateStatus(documentDetected: true, isStable: document.isStable)
            } else {
                self.overlayView.hideOverlay(animated: true)
                self.updateStatus(documentDetected: false, isStable: false)
            }
        }
    }

    /// Convertit les points Vision (normalisés, origine en bas à gauche) vers les coordonnées de la vue
    /// en tenant compte du mode resizeAspectFill de la preview et de la rotation du buffer
    private func convertVisionPointsToViewPoints(document: DocumentDetector.DetectedDocument) -> [CGPoint] {
        guard let previewLayer = previewLayer else {
            return document.points(in: overlayView.bounds.size)
        }

        // Les points Vision avec orientation .right sont dans le système de coordonnées
        // de l'image APRÈS rotation (portrait), mais layerPointConverted attend des
        // coordonnées dans le système du CAPTEUR (paysage).
        //
        // Pour une rotation .right (90° horaire):
        // - Le X de Vision devient Y du capteur
        // - Le Y de Vision devient (1 - X) du capteur
        let visionPoints = [
            document.topLeft,
            document.topRight,
            document.bottomRight,
            document.bottomLeft
        ]

        return visionPoints.map { visionPoint in
            // Transformer les coordonnées Vision (après rotation .right) vers le système capteur
            // Vision après .right: origine en bas-gauche de l'image portrait
            // Capteur: origine en bas-gauche de l'image paysage
            //
            // La transformation inverse de .right est:
            // capteurX = visionY
            // capteurY = 1 - visionX
            let capteurPoint = CGPoint(x: visionPoint.y, y: 1 - visionPoint.x)

            // Maintenant convertir vers les coordonnées de la vue
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: capteurPoint)
        }
    }
}
