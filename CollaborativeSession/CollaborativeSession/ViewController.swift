/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import RealityKit
import ARKit
import MultipeerConnectivity

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var messageLabel: MessageLabel!
    @IBOutlet weak var restartButton: UIButton!
    
    var multipeerSession: MultipeerSession?
    
    let coachingOverlay = ARCoachingOverlayView()
    
    // A dictionary to map MultiPeer IDs to ARSession ID's.
    // This is useful for keeping track of which peer created which ARAnchors.
    var peerSessionIDs = [MCPeerID: String]()
    
    var sessionIDObservation: NSKeyValueObservation?
    
    var configuration: ARWorldTrackingConfiguration?

    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)

        arView.session.delegate = self

        // Turn off ARView's automatically-configured session
        // to create and set up your own configuration.
        arView.automaticallyConfigureSession = false
        
        configuration = ARWorldTrackingConfiguration()

        // Enable a collaborative session.
        configuration?.isCollaborationEnabled = true
        
        // Enable realistic reflections.
        configuration?.environmentTexturing = .automatic

        // Begin the session.
        arView.session.run(configuration!)
        
        // Use key-value observation to monitor your ARSession's identifier.
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        setupCoachingOverlay()
        
        // Start looking for other players via MultiPeerConnectivity.
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData, peerJoinedHandler:
                                            peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
        
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true

        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:))))
        
        messageLabel.displayMessage("Tap the screen to place cubes.\nInvite others to launch this app to join you.", duration: 60.0)
    }
    
    @objc
    func handleTap(recognizer: UITapGestureRecognizer) {
        
        let location = recognizer.location(in: arView)
        
        // Attempt to find a 3D location on a horizontal surface underneath the user's touch location.
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
//        let results = arView.hitTest(location, types: .existingPlaneUsingExtent)
        
//        let tapLocation = sender.location(in: arView)
        let hitTestResults = arView.hitTest(location)
        for result in hitTestResults {
            if let entity = result.entity as? ModelEntity {
                // A ModelEntity has been tapped
                print("Tapped on ModelEntity: \(entity.name ?? "")")
                // Do whatever you want to do when a ModelEntity is tapped
                let alertController = UIAlertController(title: "Rate Entity", message: "Please rate this entity from 1 to 5", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                
                let rateAction = UIAlertAction(title: "Rate", style: .default) { _ in
                    // Get rating from user
                    if let textField = alertController.textFields?.first,
                        let ratingString = textField.text,
                        let rating = Int(ratingString) {
                            let textEntity = self.textGen(textString: "\(rating)/5", color: .black)
                            entity.addChild(textEntity)
                        }
                }
                
                alertController.addAction(cancelAction)
                alertController.addAction(rateAction)
                
                alertController.addTextField { textField in
                    textField.keyboardType = .numberPad
                }
                
                present(alertController, animated: true, completion: nil)
            }
        }
        
        if let firstResult = results.first {
            
            let alertController = UIAlertController(title: "Annotate", message: "Enter your annotation", preferredStyle: .alert)
                        alertController.addTextField()
            let addAction = UIAlertAction(title: "Add", style: .default) { [weak self, weak alertController] _ in
                guard let self = self,
                      let alertController = alertController,
                      let textField = alertController.textFields?.first,
                      let text = textField.text else {
                    return
                }
                // Add an ARAnchor at the touch location with a special name you check later in `session(_:didAdd:)`.
                let anchor = ARAnchor(name: text, transform: firstResult.worldTransform)
                arView.session.add(anchor: anchor)
            }
            alertController.addAction(addAction)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alertController.addAction(cancelAction)
            present(alertController, animated: true, completion: nil)
            
        } else {
            messageLabel.displayMessage("Can't place object - no surface found.\nLook for flat surfaces.", duration: 2.0)
            print("Warning: Object placement failed.")
        }
        
        // Check if the tap intersects with any meshes in the scene
        /*
        if let entity = arView.entity(at: location) {
            // Display rating prompt
            let alertController = UIAlertController(title: "Rate Entity", message: "Please rate this entity from 1 to 5", preferredStyle: .alert)
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            
            let rateAction = UIAlertAction(title: "Rate", style: .default) { _ in
                // Get rating from user
                if let textField = alertController.textFields?.first,
                    let ratingString = textField.text,
                    let rating = Int(ratingString) {
                        let textEntity = self.textGen(textString: "\(rating)/5", color: .black)
                        entity.addChild(textEntity)
                    }
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(rateAction)
            
            alertController.addTextField { textField in
                textField.keyboardType = .numberPad
            }
            
            present(alertController, animated: true, completion: nil)
        }
         */
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let text = anchor.name {
                let anchorEntity = AnchorEntity(anchor: anchor)
                let color = anchor.sessionIdentifier?.toRandomColor() ?? .white
                let textEntity = textGen(textString: text, color: color)
                
                anchorEntity.addChild(textEntity)
                
                //add collision
                textEntity.generateCollisionShapes(recursive: true)
                arView.installGestures([.all], for: textEntity)

                arView.scene.addAnchor(anchorEntity)
            }
        }
    }
    
    func textGen(textString: String, color: UIColor) -> ModelEntity {
        let materialVar = SimpleMaterial(color: color, roughness: 0, isMetallic: false)
        
        let depthVar: Float = 0.001
        let fontVar = UIFont.systemFont(ofSize: 0.02)
        let containerFrameVar = CGRect(x: -0.05, y: -0.1, width: 0.1, height: 0.1)
        let alignmentVar: CTTextAlignment = .center
        let lineBreakModeVar : CTLineBreakMode = .byWordWrapping
        
        let textMeshResource : MeshResource = .generateText(textString,
                                           extrusionDepth: depthVar,
                                           font: fontVar,
                                           containerFrame: containerFrameVar,
                                           alignment: alignmentVar,
                                           lineBreakMode: lineBreakModeVar)
//
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
//        meshResource.addGestureRecognizer(tapGesture)
        
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
//        textEntity.addGestureRecognizer(tapGesture)
        
//
//        textEntity.generateCollisionShapes(recursive: true)
//        textEntity.components[CollisionComponent] = CollisionComponent(
//            shapes: [.generateBox(size: 0.1)],
//            mode: .trigger,
//            filter: .sensor
//        )
//        textEntity.components[TapGestureComponent] = TapGestureComponent(for: .touchUpInside)
//        textEntity.components[TapGestureComponent]?.addTarget(self, action: #selector(handleTap(_:)))
//

        let textEntity = ModelEntity(mesh: textMeshResource, materials: [materialVar])
        return textEntity
    }
    
    /// - Tag: DidOutputCollaborationData
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let multipeerSession = multipeerSession else { return }
        if !multipeerSession.connectedPeers.isEmpty {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            else { fatalError("Unexpectedly failed to encode collaboration data.") }
            // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
        } else {
            print("Deferred sending collaboration to later because there are no peers.")
        }
    }

    func receivedData(_ data: Data, from peer: MCPeerID) {
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        }
        // ...
        let sessionIDCommandString = "SessionID:"
        if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex,
                                                                     offsetBy: sessionIDCommandString.count)...])
            // If this peer was using a different session ID before, remove all its associated anchors.
            // This will remove the old participant anchor and its geometry from the scene.
            if let oldSessionID = peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            peerSessionIDs[peer] = newSessionID
        }
    }
    
    func peerDiscovered(_ peer: MCPeerID) -> Bool {
        guard let multipeerSession = multipeerSession else { return false }
        
        if multipeerSession.connectedPeers.count > 3 {
            // Do not accept more than four users in the experience.
            messageLabel.displayMessage("A fifth peer wants to join the experience.\nThis app is limited to four users.", duration: 6.0)
            return false
        } else {
            return true
        }
    }
    /// - Tag: PeerJoined
    func peerJoined(_ peer: MCPeerID) {
        messageLabel.displayMessage("""
            A peer wants to join the experience.
            Hold the phones next to each other.
            """, duration: 6.0)
        // Provide your session ID to the new user so they can keep track of your anchors.
        sendARSessionIDTo(peers: [peer])
    }
        
    func peerLeft(_ peer: MCPeerID) {
        messageLabel.displayMessage("A peer has left the shared experience.")
        
        // Remove all ARAnchors associated with the peer that just left the experience.
        if let sessionID = peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            peerSessionIDs.removeValue(forKey: peer)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present the error that occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    @IBAction func resetTracking() {
        guard let configuration = arView.session.configuration else { print("A configuration is required"); return }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    override var prefersStatusBarHidden: Bool {
        // Request that iOS hide the status bar to improve immersiveness of the AR experience.
        return true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        // Request that iOS hide the home indicator to improve immersiveness of the AR experience.
        return true
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = arView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                arView.session.remove(anchor: anchor)
            }
        }
    }
    
    private func sendARSessionIDTo(peers: [MCPeerID]) {
        guard let multipeerSession = multipeerSession else { return }
        let idString = arView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
}
