import SwiftUI
import SceneKit

extension SCNVector3 {
    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }

    func length() -> Float {
        return sqrt(x * x + y * y + z * z)
    }
}

import ARKit
import Foundation

// MARK: - Data Structure
struct SphereData: Identifiable {
    var id = UUID() // Unique identifier for each sphere instance
    var position: SCNVector3 // 3D coordinates representing the sphere's location in space
    var transparency: CGFloat // Opacity of the sphere, ranging from 0 (fully transparent) to 1 (fully opaque)
    var name: String // Descriptive name for the sphere, useful for identification
    var radius: Float // Radius of the sphere, defining its size in the 3D scene
}

// MARK: - Lines Creator
extension SCNGeometry {
    // Creates a line geometry from two specified 3D vectors
    static func line(from vectorA: SCNVector3, to vectorB: SCNVector3) -> SCNGeometry {
        let vertices = [vectorA, vectorB] // Array holding the start and end points of the line
        let source = SCNGeometrySource(vertices: vertices) // Geometry source defining the vertex data
        
        let indices: [Int32] = [0, 1] // Indices defining the order of vertices to create the line
        let element = SCNGeometryElement(indices: indices, primitiveType: .line) // Geometry element specifying line primitive
        
        return SCNGeometry(sources: [source], elements: [element]) // Returns the created line geometry
    }
}

// MARK: - ARSCNViewRepresentable
struct ARSCNViewRepresentable: UIViewRepresentable {
    let scene: SCNScene // The 3D scene to display in the AR view
    @Binding var cameraPosition: SCNVector3 // The position of the camera in the scene
    @Binding var selectedStarInfo: String // Information about the currently selected star
    @Binding var selectedStarName: String // Name of the currently selected star
    @Binding var isLineDrawingMode: Bool // Indicates if the line drawing mode is active
    @Binding var selectedStarsForLine: [SCNNode] // Nodes of the selected stars for line drawing
    @Binding var lines: [SCNNode] // Nodes representing drawn lines
    @Binding var showNametags: Bool // Determines if nametags for stars should be shown

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView() // Create an instance of ARSCNView
        arView.delegate = context.coordinator // Set the delegate to handle AR updates
        arView.scene = scene // Assign the 3D scene to the AR view
        arView.autoenablesDefaultLighting = true // Enable default lighting for better visibility
        arView.backgroundColor = UIColor.black // Set the background color to black
        arView.allowsCameraControl = false // Disable user camera control
        
        let configuration = ARWorldTrackingConfiguration() // Create a configuration for AR tracking
        configuration.worldAlignment = .gravity // Align the world to gravity
        arView.session.run(configuration) // Start the AR session with the configuration
        
        // Position the camera node at the specified camera position
        if let cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
            cameraNode.position = cameraPosition // Set the camera's position
            cameraNode.eulerAngles = SCNVector3Zero // Reset camera's rotation
        }
        
        // Add a tap gesture recognizer to the AR view
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture) // Register tap gesture

        // Add a pan gesture recognizer to the AR view
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap(_:)))
        arView.addGestureRecognizer(panGesture) // Register pan gesture

        return arView // Return the configured ARSCNView
    }

    
    func updateUIView(_ arView: ARSCNView, context: Context) {
        // Loop through all lines to add them to the scene if they are not already parented
        for line in lines {
            if line.parent == nil {
                scene.rootNode.addChildNode(line) // Add line to the root node of the scene
            }
        }
        
        // Enumerate through child nodes of the scene root node
        scene.rootNode.enumerateChildNodes { (node, stop) in
            // Check if the node is a "Nametag"
            if node.name == "Nametag" {
                node.isHidden = !showNametags // Show or hide nametags based on the showNametags flag
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        // Create and return a Coordinator instance for managing delegate callbacks
        Coordinator(self)
    }

    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARSCNViewRepresentable
        var lastPanLocation: CGPoint = .zero // Stores the last pan location
        var yaw: Float = 0.0 // Yaw rotation for camera
        var pitch: Float = 0.0 // Pitch rotation for camera

        // Initializes the Coordinator with a reference to the parent view
        init(_ parent: ARSCNViewRepresentable) {
            self.parent = parent
        }

        // Handles tap gestures to select a star
        @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            let arView = gestureRecognizer.view as! ARSCNView // Get the AR view
            let location = gestureRecognizer.location(in: arView) // Get tap location
            let hitResults = arView.hitTest(location, options: nil) // Perform hit test

            if let result = hitResults.first { // Check if any node was hit
                let selectedNode = result.node // Get the selected node
                
                // If the selected node is a sphere (star)
                if selectedNode.geometry is SCNSphere {
                    // Find the camera node in the scene
                    if let cameraNode = arView.scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
                        let selectedPosition = selectedNode.position // Get the position of the selected star
                        
                        // Update the camera position to focus on the selected star
                        cameraNode.position = SCNVector3(selectedPosition.x, selectedPosition.y, selectedPosition.z + 1)
                        cameraNode.look(at: selectedPosition) // Set camera to look at the star
                    }
                }
            }
        }

        // Handles pan gestures to rotate the camera
        @objc func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
            guard let arView = gestureRecognizer.view as? ARSCNView,
                  let cameraNode = arView.scene.rootNode.childNodes.first(where: { $0.camera != nil }) else {
                return // Exit if the AR view or camera node is not found
            }

            let translation = gestureRecognizer.translation(in: arView) // Get translation of the pan gesture
            let rotationX = Float(translation.y) * (Float.pi / 180.0) // Calculate rotation around X-axis
            let rotationY = Float(translation.x) * (Float.pi / 180.0) // Calculate rotation around Y-axis

            // Update camera rotation based on gesture translation
            cameraNode.eulerAngles.x -= rotationX
            cameraNode.eulerAngles.y -= rotationY

            gestureRecognizer.setTranslation(.zero, in: arView) // Reset translation for next gesture
        }

        // Updates the positions of stars in the scene
        func updateStarsPosition() {
            if let cameraNode = parent.scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
                let cameraPosition = cameraNode.position // Get the camera's position
                
                // Iterate over all star nodes in the scene
                for starNode in parent.scene.rootNode.childNodes where starNode.name != "Nametag" {
                    let distanceFromCamera = (starNode.position - cameraPosition).length() // Calculate distance from camera
                    
                    // Potentially use the distance for some functionality (not implemented here)
                }
            }
        }
        
        // Creates a line node between two points in 3D space
        func createLineNode(from: SCNVector3, to: SCNVector3) -> SCNNode {
            let line = SCNGeometry.line(from: from, to: to) // Create line geometry
            let lineNode = SCNNode(geometry: line) // Create a node with the line geometry
            // Set a random color for the line
            lineNode.geometry?.firstMaterial?.diffuse.contents = UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1.0
            )
            lineNode.geometry?.firstMaterial?.lightingModel = .constant // Set lighting model for the line
            return lineNode // Return the line node
        }
    }

}

// MARK: - ContentView
struct ContentView: View {
    @State private var spheres: [SphereData] = [] // Holds data for all spheres (stars) in the scene
    @State private var showNametags: Bool = true // Determines whether to display nametags for stars

    @State private var cameraPosition = SCNVector3(x: 0, y: 0, z: 0) // Current position of the camera in the scene
    @State private var selectedStarInfo = "Coordinates: (x: 0, y: 0, z: 0)\nBrightness: 0.0" // Info about the selected star
    @State private var selectedStarName = "You are in the star: CoRoT-19,790.6630000" // Name of the currently selected star
    @State private var isLineDrawingMode = false // Indicates if the line drawing mode is active
    @State private var selectedStarsForLine: [SCNNode] = [] // Stores selected stars for drawing lines between them
    @State private var lines: [SCNNode] = [] // Holds line nodes that represent connections between stars

    @State private var scene = SCNScene() // The main 3D scene containing all the elements

    
    var body: some View {
        ZStack {
            ARSCNViewRepresentable(
                scene: scene, // The 3D scene containing all the stars and elements
                cameraPosition: $cameraPosition, // Binding to the camera position state variable
                selectedStarInfo: $selectedStarInfo, // Binding to the selected star information state variable
                selectedStarName: $selectedStarName, // Binding to the name of the currently selected star
                isLineDrawingMode: $isLineDrawingMode, // Binding to indicate if the line drawing mode is active
                selectedStarsForLine: $selectedStarsForLine, // Binding to the list of selected stars for line drawing
                lines: $lines, // Binding to the array of line nodes for visualization
                showNametags: $showNametags // Binding to control the visibility of star nametags
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Button(action: {
                        showNametags.toggle()
                    }) {
                        Text(showNametags ? "Hide Nametags" : "Show Nametags") // Display text based on the state of showNametags
                            .padding() // Add padding around the text for better spacing
                            .background(Color.blue) // Set the background color of the text to blue
                            .foregroundColor(.white) // Change the text color to white for contrast
                            .cornerRadius(8) // Round the corners of the background to make it look visually appealing
                    }
                    .padding([.top, .leading])
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text(selectedStarName) // Displays the name of the currently selected star
                            .padding(5) // Adds padding around the text for better spacing
                            .background(Color.white.opacity(0.8)) // Sets a semi-transparent white background for the text
                            .cornerRadius(10) // Rounds the corners of the background for a smoother look
                            .font(.caption) // Sets the font size to caption for a smaller, less intrusive text
                            .foregroundColor(.black) // Changes the text color to black for good contrast against the background

                        Text(selectedStarInfo) // Displays detailed information about the selected star
                            .padding(5) // Adds padding around the text for improved spacing
                            .background(Color.white.opacity(0.8)) // Sets a semi-transparent white background for the text
                            .cornerRadius(10) // Rounds the corners of the background for a cohesive design
                            .font(.caption) // Sets the font size to caption for consistency in text size
                            .foregroundColor(.black) // Changes the text color to black for readability

                    }
                    .padding([.top, .trailing])
                }
                
                Spacer()
                
                HStack {
                    Button(action: {
                        isLineDrawingMode.toggle()
                    }) {
                        Text(isLineDrawingMode ? "Enable Constellations" : "Draw Constellations") // Displays text based on the state of isLineDrawingMode
                            .padding() // Adds padding around the text for better spacing
                            .background(isLineDrawingMode ? Color.red : Color.green) // Sets the background color based on the drawing mode; red if enabled, green if not
                            .foregroundColor(.white) // Sets the text color to white for good contrast against the background
                            .cornerRadius(8) // Rounds the corners of the background for a smoother look

                    }
                    .padding()
                    
                    Spacer()
    
                    Button(action: {
                  
                        lines.forEach { $0.removeFromParentNode() }
                        lines.removeAll()
                    }) {
                        Text("Erase Lines") // Displays the text "Erase Lines"
                            .padding() // Adds padding around the text for better spacing
                            .background(Color.red) // Sets the background color of the text to red, indicating a destructive action
                            .foregroundColor(.white) // Changes the text color to white for good contrast against the red background
                            .cornerRadius(8) // Rounds the corners of the background for a smoother appearance

                    }
                    .padding()
                }
                .padding(.bottom)
            }
        }
        .onAppear {
            loadCSVData()
            setupScene()
        }
    }
    
    func loadCSVData() {
        // Attempt to locate the CSV file in the app's bundle
        guard let url = Bundle.main.url(forResource: "datos2", withExtension: "csv") else {
            print("No CSV Available.") // Print an error message if the file is not found
            return
        }
        
        do {
            // Read the contents of the CSV file as a String
            let data = try String(contentsOf: url)
            // Split the data into rows based on new line characters
            let rows = data.components(separatedBy: .newlines)
            var loadedSpheres: [SphereData] = [] // Initialize an empty array to hold SphereData objects
            
            // Iterate through each row, skipping the first (header) row
            for row in rows.dropFirst() {
                // Split each row into columns based on commas
                let columns = row.components(separatedBy: ",")
                // Check if the row contains exactly 6 columns
                if columns.count == 6 {
                    // Attempt to extract and convert necessary values from the columns
                    if let radius0 = Float(columns[1]),
                       let ra0 = Float(columns[2]),
                       let dec0 = Float(columns[3]),
                       let transparencyValue = Double(columns[4]),
                       let tamaño1 = Float(columns[5]),
                       transparencyValue >= -4, transparencyValue <= 4.0
                    {
                        let tamaño = tamaño1 / 10 // Scale tamaño1 to a smaller size
                        let name = columns[0] // Get the name from the first column
                        
                        // Convert right ascension and declination from degrees to radians
                        let ra = ra0 * Float.pi / 180
                        let dec = (90 - dec0) * Float.pi / 180
                        let radius = radius0 // Use the radius directly
                        
                        // Calculate the x, y, and z coordinates based on spherical coordinates
                        let x = radius * sin(ra) * cos(dec)
                        let y = radius * sin(ra) * sin(dec)
                        let z = radius * cos(ra)
                        
                        // Create a SphereData object with the calculated position and properties
                        let sphereData = SphereData(
                            position: SCNVector3(x, y, z), // Position calculated above
                            transparency: CGFloat(transparencyValue), // Convert transparency to CGFloat
                            name: name, // Set the name
                            radius: tamaño // Set the scaled radius
                        )
                        loadedSpheres.append(sphereData) // Add the sphere data to the array
                    }
                }
            }
            self.spheres = loadedSpheres // Assign the loaded spheres to the spheres property
        } catch {
            // Handle any errors that occur while reading the CSV file
            print("Error al leer el archivo CSV: \(error)")
        }
    }

    func setupScene() {
        // Set the background color of the scene to black
        scene.background.contents = UIColor.black
        
        // Create a container node to hold all the sphere nodes
        let containerNode = SCNNode()
        containerNode.name = "containerNode" // Name the container node for identification
        scene.rootNode.addChildNode(containerNode) // Add the container to the root node of the scene
        
        // Call the function to add lighting to the scene
        addLights(to: scene)
        
        // Iterate through the loaded spheres to create SCNSphere objects
        for sphereData in spheres {
            // Create a sphere geometry with the specified radius
            let sphere = SCNSphere(radius: CGFloat(sphereData.radius))
            let material = SCNMaterial() // Create a new material for the sphere
            material.diffuse.contents = UIColor.white // Set the sphere's color to white
            material.transparency = sphereData.transparency // Set the transparency from sphere data
            material.blendMode = .alpha // Set the blend mode to alpha for transparency
            sphere.materials = [material] // Assign the material to the sphere
            
            // Create a node for the sphere geometry
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = sphereData.position // Set the position of the sphere node
            sphereNode.name = sphereData.name // Name the sphere node
            containerNode.addChildNode(sphereNode) // Add the sphere node to the container node
            
            // Create a text geometry for the sphere's name
            let textGeometry = SCNText(string: sphereData.name, extrusionDepth: 0.1)
            textGeometry.font = UIFont.systemFont(ofSize: 10) // Set the font size for the text
            textGeometry.flatness = 0.1 // Set the flatness for rendering the text
            textGeometry.firstMaterial?.diffuse.contents = UIColor.white // Set text color to white
            
            // Create a node for the text geometry
            let textNode = SCNNode(geometry: textGeometry)
            textNode.scale = SCNVector3(0.02, 0.02, 0.02) // Scale the text down for proper display
            textNode.position = SCNVector3(
                sphereData.position.x, // X position aligned with the sphere
                sphereData.position.y + Float(sphereData.radius) + 0.5, // Y position above the sphere
                sphereData.position.z // Z position aligned with the sphere
            )
            textNode.name = "Nametag" // Name the text node for identification
            
            // Create a billboard constraint to keep the text facing the camera
            let billboardConstraint = SCNBillboardConstraint()
            billboardConstraint.freeAxes = .all // Allow the text to rotate freely in all directions
            textNode.constraints = [billboardConstraint] // Apply the constraint to the text node
            
            // Add the text node to the container node
            containerNode.addChildNode(textNode)
        }
        
        // Create a camera and set its properties
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera // Assign the camera to the camera node
        cameraNode.position = cameraPosition // Set the position of the camera node
        cameraNode.eulerAngles = SCNVector3Zero // Reset the camera's rotation
        scene.rootNode.addChildNode(cameraNode) // Add the camera node to the scene
    }

    func addLights(to scene: SCNScene) {
        // Create a directional light node
        let directionalLightNode = SCNNode()
        directionalLightNode.light = SCNLight() // Instantiate a new SCNLight
        directionalLightNode.light?.type = .directional // Set the light type to directional
        directionalLightNode.light?.castsShadow = false // Disable shadows for this light
        // Set the direction of the light (angles in radians)
        directionalLightNode.eulerAngles = SCNVector3(-Float.pi / 3, 0, 0)
        // Add the directional light node to the scene's root node
        scene.rootNode.addChildNode(directionalLightNode)

        // Create an ambient light node
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight() // Instantiate another SCNLight
        ambientLightNode.light?.type = .ambient // Set the light type to ambient
        ambientLightNode.light?.intensity = 300 // Set the intensity of the ambient light
        // Set the color of the ambient light to a soft white
        ambientLightNode.light?.color = UIColor(white: 0.8, alpha: 1.0)
        // Add the ambient light node to the scene's root node
        scene.rootNode.addChildNode(ambientLightNode)
    }
}

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

 
