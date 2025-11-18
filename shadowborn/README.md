# Character Control

### Set up your joystick to control the CharacterBody3D. This node should be added as a child of CharacterBody3D, and you should configure your joystick in the Godot inspector (it comes pre-configured).

### How it works:

### The left joystick moves the CharacterBody3D, the right joystick rotates the SpringArm with the camera, the A button makes the character jump, the R button locks the camera, and holding the L button switches to first-person view. There’s no need to create a SpringArm and camera, as this is already handled.

### Note: Character Control already applies gravity to CharacterBody3D, so you should not add another script that handles gravity.
