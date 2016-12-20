# DaydreamController

Supports the Google VR Daydream View Controller on iOS.
This is a first working hack.

Create a new iOS Game project (SceneKit) with Xcode, add the DaydreamController.swift file
and modify GameViewController.swift like this:

	class GameViewController: UIViewController
	{
	    let controller = DaydreamController()
	    var ship: SCNNode!
	    var orientation0 = GLKQuaternionIdentity
	    
	    override func viewDidLoad() {
	        super.viewDidLoad()
	        
	        controller.delegate = self
	        controller.connect()
	            
	            ....
	            
	            // retrieve the ship node
	            ship = scene.rootNode.childNode(withName: "ship", recursively: true)!
	            
	            // animate the 3d object
	            // ship.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 2, z: 0, duration: 1)))
	            
	        ....
	    }
	}
	
	extension GameViewController: DaydreamControllerDelegate
	{
	    func daydreamControllerDidConnect(_ controller: DaydreamController) {
	        print("Press the home button to recenter the controller's orientation")
	    }
	    
	    func daydreamControllerDidUpdate(_ controller: DaydreamController, state: DaydreamController.State) {
	        if state.homeButtonDown {
	            orientation0 = GLKQuaternionInvert(state.orientation)
	        }
	        
	        let q = GLKQuaternionMultiply(orientation0 ,state.orientation)
	        ship.orientation = SCNQuaternion(q.x, q.y, q.z, q.w)
	    }
	}
