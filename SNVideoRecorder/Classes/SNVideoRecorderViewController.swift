//
//  SNVideoRecorderViewController.swift
//  Pods
//
//  Created by Dair Diaz on 24/08/17.
//
//

import UIKit
import AVFoundation
import NVActivityIndicatorView

enum SNCaptureMode:UInt8 {
    case video = 0
    case photo = 1
}

public class SNVideoRecorderViewController: UIViewController {
    public weak var delegate:SNVideoRecorderDelegate?
    var session:AVCaptureSession?
    var videoInput:AVCaptureDeviceInput?
    var audioInput:AVCaptureDeviceInput?
    var movieFileOutput:AVCaptureMovieFileOutput?
    var imageFileOutput:AVCaptureStillImageOutput?
    public var closeOnCapture:Bool = true
    public var finalURL:URL?
    public var maxSecondsToRecord = 59
    public var initCameraPosition:AVCaptureDevice.Position = .front
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    // flash light button options
    public var flashLightOnIcon:UIImage?
    public var flashLightOffIcon:UIImage?
    
    // confirmation view button text
    public var agreeText:String = NSLocalizedString("Ok", comment: "")
    public var discardText:String = NSLocalizedString("Discard", comment: "")
    
    // components
    var previewLayer:AVCaptureVideoPreviewLayer?
    let countDown:SNRecordingCountDown = {
        let v = SNRecordingCountDown()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    let recordOption:SNRecordButton = {
        let v = SNRecordButton()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    public let flashLightOption:UIButton = {
        let v = UIButton(type: .custom)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.init(white: 0, alpha: 0.3)
        v.tintColor = .white
        return v
    }()
    public let switchCameraOption:UIButton = {
        let v = UIButton(type: .custom)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.init(white: 0, alpha: 0.3)
        v.tintColor = .white
        return v
    }()
    public let closeOption:UIButton = {
        let v = UIButton()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.init(white: 0, alpha: 0.3)
        v.tintColor = .white
        return v
    }()
    let loading:NVActivityIndicatorView = {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 50)
        let v = NVActivityIndicatorView(frame: rect, type: .ballClipRotatePulse, color: .white, padding: 5.0)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        flashLightOption.setImage(flashLightOnIcon?.withRenderingMode(.alwaysTemplate), for: .normal)
        
        addViews()
        setupViews()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setupNavigationBar()
        
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) ==  .authorized {
            let _ = connect(withDeviceAt: initCameraPosition)
        } else {
            switchCameraOption.isEnabled = false
            flashLightOption.isEnabled = false
            recordOption.isEnabled = false
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) -> Void in
                if granted {
                    let _ = self.connect(withDeviceAt: self.initCameraPosition)
                } else {
                    DispatchQueue.main.async {
                        let title = NSLocalizedString("permission_camera_title", comment: "")
                        let message = NSLocalizedString("permission_camera_message", comment: "")
                        self.showPermissionAlert(title: title, message: message)
                    }
                }
            })
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        previewLayer?.frame.size = view.frame.size
        closeOption.layer.cornerRadius = closeOption.frame.width / 2
        switchCameraOption.layer.cornerRadius = switchCameraOption.frame.width / 2
        flashLightOption.layer.cornerRadius = switchCameraOption.layer.cornerRadius
    }
    
    public override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        switch UIDevice.current.orientation {
        case .portrait:
            previewLayer?.connection?.videoOrientation = .portrait
        case .landscapeLeft:
            previewLayer?.connection?.videoOrientation = .landscapeRight
        default:
            previewLayer?.connection?.videoOrientation = .landscapeLeft
        }
        
        recordOption.cancel()
    }
    
    func createSession(device: AVCaptureDevice, audioDevice: AVCaptureDevice) {
        session = AVCaptureSession()
        session?.beginConfiguration()
        do {
            try device.lockForConfiguration()
            videoInput = try AVCaptureDeviceInput(device: device)
            audioInput = try AVCaptureDeviceInput(device: audioDevice)
        } catch let error {
            print(error)
        }
        
        if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }
        
        guard let s = session else {
            return
        }
        
        if s.canAddInput(audioInput!) {
            s.addInput(audioInput!)
        }
        if s.canAddInput(videoInput!) {
            s.addInput(videoInput!)
        }
        
        // video output
        if let output = movieFileOutput {
            if s.canAddOutput(output) {
                s.addOutput(output)
            }
        }
        
        // photo output
        if let output = imageFileOutput {
            if s.canAddOutput(output) {
                s.addOutput(output)
            }
        }
        
        updatePreview(session: s)
        
        device.unlockForConfiguration()
        s.commitConfiguration()
        s.startRunning()
    }
    
    func destroySession() {
        session?.removeInput(videoInput!)
        videoInput = nil
        
        if session != nil {
            if session!.isRunning {
                session?.stopRunning()
                session = nil
            }
        }
    }
    
    func updatePreview(session:AVCaptureSession) {
        previewLayer?.session = session
    }
    
    func cameraWithPosition(position: AVCaptureDevice.Position) -> (audio:AVCaptureDevice?, video:AVCaptureDevice?) {
        let devices = AVCaptureDevice.devices()
        var audio:AVCaptureDevice?
        var video:AVCaptureDevice?
        for device in devices {
            if (device as AnyObject).hasMediaType(AVMediaType.video) {
                if (device as AnyObject).position == position {
                    video = device
                }
            }
            
            if (device as AnyObject).hasMediaType(AVMediaType.audio) {
                audio = device
            }
        }
        
        return (audio, video)
    }
    
    func addViews() {
        // camera preview
        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.layer.insertSublayer(previewLayer!, at: 0)
        view.addSubview(loading)
        
        // controls
        view.addSubview(countDown)
        view.addSubview(closeOption)
        view.addSubview(flashLightOption)
        view.addSubview(switchCameraOption)
        view.addSubview(recordOption)
        
        flashLightOption.addTarget(self, action: #selector(flashLightHandler), for: .touchUpInside)
        closeOption.addTarget(self, action: #selector(closeHandler), for: .touchUpInside)
        switchCameraOption.addTarget(self, action: #selector(switchCameraHandler), for: .touchUpInside)
    }
    
    func setupViews() {
        // count down
        countDown.widthAnchor.constraint(equalToConstant: 80).isActive = true
        countDown.heightAnchor.constraint(equalToConstant: 30).isActive = true
        countDown.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        countDown.topAnchor.constraint(equalTo: view.topAnchor, constant: 15).isActive = true
        
        // close option
        closeOption.widthAnchor.constraint(equalToConstant: 30).isActive = true
        closeOption.heightAnchor.constraint(equalTo: closeOption.widthAnchor).isActive = true
        closeOption.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -15).isActive = true
        closeOption.centerYAnchor.constraint(equalTo: countDown.centerYAnchor).isActive = true
        
        // flash light
        flashLightOption.widthAnchor.constraint(equalToConstant: 45).isActive = true
        flashLightOption.heightAnchor.constraint(equalTo: switchCameraOption.widthAnchor).isActive = true
        flashLightOption.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 15).isActive = true
        flashLightOption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -15).isActive = true
        
        // switch camera
        switchCameraOption.widthAnchor.constraint(equalToConstant: 45).isActive = true
        switchCameraOption.heightAnchor.constraint(equalTo: switchCameraOption.widthAnchor).isActive = true
        switchCameraOption.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -15).isActive = true
        switchCameraOption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -15).isActive = true
        
        // record option
        recordOption.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        recordOption.widthAnchor.constraint(equalToConstant: 60).isActive = true
        recordOption.heightAnchor.constraint(equalTo: recordOption.widthAnchor).isActive = true
        recordOption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20).isActive = true
        
        // loading
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loading.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }
    
    func setupNavigationBar() {
        navigationController?.navigationBar.isHidden = true
        navigationController?.navigationBar.isTranslucent = false
    }
    
    @objc func switchCameraHandler(sender:UIButton) {
        if initCameraPosition == .front {
            initCameraPosition = .back
        } else {
            initCameraPosition = .front
        }
        
        destroySession()
        let _ = connect(withDeviceAt: initCameraPosition)
    }
    
    @objc func flashLightHandler(sender:UIButton) {
        if let device = AVCaptureDevice.default(for: AVMediaType.video) {
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    let state = !device.isTorchActive
                    device.torchMode = state ? .on : .off
                    if state {
                        sender.setImage(flashLightOffIcon?.withRenderingMode(.alwaysTemplate), for: .normal)
                    } else {
                        sender.setImage(flashLightOnIcon?.withRenderingMode(.alwaysTemplate), for: .normal)
                    }
                    device.unlockForConfiguration()
                } catch {
                    print(error)
                }
            }
        } else {
            print("no device camera")
        }
    }
    
    @objc func closeHandler(sender:UIButton) {
        closeView()
    }
    
    func connect(withDeviceAt position: AVCaptureDevice.Position) -> Bool {
        let devices = cameraWithPosition(position: position)
        guard let video = devices.video else {
            return false
        }
        guard let audio = devices.audio else {
            return false
        }
        
        DispatchQueue.main.async {
            if video.hasTorch {
                self.flashLightOption.isEnabled = true
                self.flashLightOption.isHidden = false
            } else {
                self.flashLightOption.isEnabled = false
                self.flashLightOption.isHidden = true
            }
        }
        
        // video output
        movieFileOutput = AVCaptureMovieFileOutput()
        let maxDuration:CMTime = CMTimeMake(600, 10)
        movieFileOutput?.maxRecordedDuration = maxDuration
        movieFileOutput?.minFreeDiskSpaceLimit = 1024 * 1024
        
        // image output
        imageFileOutput = AVCaptureStillImageOutput()
        imageFileOutput?.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        
        createSession(device: video, audioDevice: audio)
        recordOption.delegate = self
        countDown.setup(seconds: maxSecondsToRecord)
        countDown.delegate = self
        return false
    }
    
    func showPermissionAlert(title:String, message:String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("configuration", comment: ""), style: .default) { action in
            guard let settingsUrl = URL(string: UIApplicationOpenSettingsURLString) else {
                return
            }
            
            if UIApplication.shared.canOpenURL(settingsUrl) {
                if #available(iOS 10.0, *) {
                    UIApplication.shared.open(settingsUrl, completionHandler: nil)
                } else {
                    UIApplication.shared.openURL(settingsUrl)
                }
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    func closeView() {
        if let navigation = navigationController {
            let _ = navigation.popViewController(animated: true)
        } else {
            dismiss(animated: true) {
                print("done")
            }
        }
    }
}

extension SNVideoRecorderViewController: SNVideoRecorderViewProtocol {
    
}

extension SNVideoRecorderViewController: AVCaptureFileOutputRecordingDelegate {
    
    public func fileOutput(_ captureOutput: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        
    }
    
    public func fileOutput(_ captureOutput: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let randomName = ProcessInfo.processInfo.globallyUniqueString
        let videoFilePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(randomName).appendingPathExtension("mp4")
        
        if FileManager.default.fileExists(atPath: videoFilePath.absoluteString) {
            do {
                try FileManager.default.removeItem(atPath: videoFilePath.absoluteString)
            }
            catch {
                
            }
        }
        
        let sourceAsset = AVURLAsset(url: outputFileURL)
        let export: AVAssetExportSession = AVAssetExportSession(asset: sourceAsset, presetName: AVAssetExportPresetMediumQuality)!
        export.outputFileType = AVFileType.mp4
        export.outputURL = videoFilePath
        export.shouldOptimizeForNetworkUse = true
        let start = CMTimeMakeWithSeconds(0.0, 0)
        let range = CMTimeRangeMake(start, sourceAsset.duration)
        export.timeRange = range
        export.exportAsynchronously { () -> Void in
            DispatchQueue.main.async(execute: {
                self.loading.stopAnimating()
                self.recordOption.isEnabled = true
            })
            switch export.status {
            case .completed:
                DispatchQueue.main.async(execute: {
                    let vc = SNVideoViewerViewController()
                    vc.modalPresentationStyle = .overCurrentContext
                    vc.delegate = self
                    vc.url = videoFilePath
                    self.present(vc, animated: false, completion: nil)
                })
            case  .failed:
                print("failed \(String(describing: export.error))")
            case .cancelled:
                print("cancelled \(String(describing: export.error))")
            default:
                print("complete")
            }
        }
    }
}

extension SNVideoRecorderViewController: SNRecordButtonDelegate {
    
    func didStart(mode:SNCaptureMode) {
        if mode == .video {
            let randomName = ProcessInfo.processInfo.globallyUniqueString
            let filePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(randomName).appendingPathExtension("mp4")
            
            movieFileOutput?.startRecording(to: filePath, recordingDelegate: self)
            countDown.start(on: maxSecondsToRecord)
        } else {
            if let videoConnection = imageFileOutput?.connection(with: AVMediaType.video) {
                imageFileOutput?.captureStillImageAsynchronously(from: videoConnection) {
                    (buffer, error) -> Void in
                    if let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer!) {
                        let vc = SNImageViewerViewController()
                        vc.modalPresentationStyle = .overCurrentContext
                        vc.image = UIImage(data: imageData)
                        vc.delegate = self
                        self.present(vc, animated: false, completion: nil)
                    }
                }
            }
        }
    }
    
    func didEnd(isCanceled:Bool) {
        guard let s = session else {
            return
        }
        
        countDown.pause()
        if !isCanceled {
            s.stopRunning()
            recordOption.isEnabled = false
            loading.startAnimating()
        } else {
            countDown.setup(seconds: maxSecondsToRecord)
        }
    }
}

extension SNVideoRecorderViewController: SNRecordingCountDownDelegate {
    
    func countDown(didStartAt time: TimeInterval) {
        print("empezó el conteo regresivo")
    }
    
    func countDown(didPauseAt time: TimeInterval) {
        print("el usuario ha detenido el conteo regresivo antes de finalizar")
    }
    
    func countDown(didFinishAt time: TimeInterval) {
        print("terminó el tiempo máximo de grabación")
    }
}

extension SNVideoRecorderViewController: SNImageViewerDelegate {
    
    func imageView(finishWithAgree agree: Bool, andImage image: UIImage?) {
        if agree {
            guard let img = image else {
                return
            }
            
            delegate?.videoRecorder(withImage: img)
            
            if closeOnCapture {
                closeView()
            }
        }
    }
}

extension SNVideoRecorderViewController: SNVideoViewerDelegate {
    
    func videoView(finishWithAgree agree: Bool, andURL url: URL?) {
        if agree {
            guard let value = url else {
                return
            }
            
            self.delegate?.videoRecorder(withVideo: value)
            
            if closeOnCapture {
                closeView()
            }
        }
    }
}
