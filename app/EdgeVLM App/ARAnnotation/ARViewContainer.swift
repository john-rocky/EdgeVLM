//
// ARViewContainer.swift
// EdgeVLM
//
// UIViewRepresentable wrapper for ARSCNView.
// Handles tap gestures, raycasting, and annotation node management.
//

#if os(iOS)
import SwiftUI
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var annotations: [ARAnnotation]
    var onTap: (CVPixelBuffer, simd_float4x4) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
        arView.delegate = context.coordinator
        arView.autoenablesDefaultLighting = true

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        return arView
    }

    func updateUIView(_ arView: ARSCNView, context: Context) {
        context.coordinator.syncAnnotations(arView: arView, annotations: annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSCNViewDelegate {
        var onTap: (CVPixelBuffer, simd_float4x4) -> Void
        private var addedAnnotationIDs: Set<UUID> = []

        init(onTap: @escaping (CVPixelBuffer, simd_float4x4) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARSCNView else { return }
            let location = gesture.location(in: arView)

            // Raycast to find a 3D position on estimated planes
            if let query = arView.raycastQuery(
                from: location, allowing: .estimatedPlane, alignment: .any
            ),
                let result = arView.session.raycast(query).first
            {
                if let frame = arView.session.currentFrame?.capturedImage {
                    onTap(frame, result.worldTransform)
                }
            }
        }

        /// Synchronise SceneKit nodes with the current annotation array.
        func syncAnnotations(arView: ARSCNView, annotations: [ARAnnotation]) {
            // Remove all nodes when the annotation list is cleared
            if annotations.isEmpty {
                arView.scene.rootNode.childNodes
                    .filter { $0.name?.starts(with: "annotation_") == true }
                    .forEach { $0.removeFromParentNode() }
                addedAnnotationIDs.removeAll()
                return
            }

            // Add nodes for newly created annotations
            for annotation in annotations where !addedAnnotationIDs.contains(annotation.id) {
                addedAnnotationIDs.insert(annotation.id)

                let textNode = createTextNode(annotation.text)
                textNode.name = "annotation_\(annotation.id.uuidString)"
                textNode.simdTransform = annotation.transform
                textNode.simdPosition.y += 0.05  // Float slightly above the surface

                // Billboard constraint so the label always faces the camera
                let billboardConstraint = SCNBillboardConstraint()
                billboardConstraint.freeAxes = [.Y]
                textNode.constraints = [billboardConstraint]

                arView.scene.rootNode.addChildNode(textNode)
            }
        }

        // MARK: - Node creation helpers

        /// Build a SceneKit node containing the annotation text with a background panel.
        private func createTextNode(_ text: String) -> SCNNode {
            let textGeometry = SCNText(string: text, extrusionDepth: 0.5)
            textGeometry.font = UIFont.systemFont(ofSize: 3, weight: .medium)
            textGeometry.firstMaterial?.diffuse.contents = UIColor.white
            textGeometry.firstMaterial?.isDoubleSided = true
            textGeometry.flatness = 0.1

            let textNode = SCNNode(geometry: textGeometry)
            let (min, max) = textNode.boundingBox
            let dx = (max.x - min.x) / 2
            let dy = (max.y - min.y) / 2
            textNode.pivot = SCNMatrix4MakeTranslation(dx, dy, 0)
            textNode.scale = SCNVector3(0.005, 0.005, 0.005)

            // Semi-transparent background plane behind the text
            let bgNode = SCNNode(
                geometry: SCNPlane(
                    width: CGFloat(max.x - min.x + 2) * 0.005,
                    height: CGFloat(max.y - min.y + 1) * 0.005
                )
            )
            bgNode.geometry?.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
            bgNode.geometry?.firstMaterial?.isDoubleSided = true
            bgNode.position = SCNVector3(0, 0, -0.001)

            let containerNode = SCNNode()
            containerNode.addChildNode(textNode)
            containerNode.addChildNode(bgNode)
            return containerNode
        }
    }
}
#endif
