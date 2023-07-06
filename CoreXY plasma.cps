/*

CoreXY post processor for milling and laser/plasma cutting.

Some design points:
- Setup operation types: Milling, Water/Laser/Plasma
- Only support MM units (inches may work with custom start gcode - NOT TESTED)
- XY and Z independent travel speeds. Rapids are done with G1.
- Arcs support on XY plane
- Tested in Marlin 1.1.0RC8
- Tested with LCD display and SD card (built in tool change require printing from SD and LCD to restart)
- Support for 3 different laser power using "cutting modes" (through, etch, vaporize)

*/


// user-defined properties
properties = {
  cutterOn:  "M2106",                // GCode command to turn on the plasma
  cutterOff: "M2107",                // Gcode command to turn off the plasma
  _thcVoltage: 125,					// Set the V<thcVoltage> in V. M2106 parameter
  _delay: 100,						// Set the D<delayTime> in ms. M2106 parameter
  _cutHeight: 6.4,					// Set the H<cutHeight> in mm. M2106 parameter
  _initialHeight: 6.4,				// Set the I<initialHeight> in mm. M2106 parameter
  _feedSpeed: 4000,	      			// Feed speed in mm/minute
  _travelSpeedXY: 2500,             // High speed for travel movements X & Y (mm/min)
  travelSpeedZ: 900,                // High speed for travel movements Z (mm/min)
  _thcStepSize: 0.1,						// Step size to divide feed movements into small G1 moves
  _thcHeightIncrement: 0.1,						// Increment to lower or lift Z-axis for every G1 move. M2106 parameter.
};

// Internal properties
extension = "gcode";
setCodePage("ascii");
certificationLevel = 2;
capabilities = CAPABILITY_JET;
description = "CoreXY Plasma Cutter THC";
vendor = "Solhaga";
useSmoothing = true;

// Formats
var xyzFormat = createFormat({decimals:3});
var feedFormat = createFormat({decimals:0});

// Linear outputs
var xOutput = createVariable({prefix:" X"}, xyzFormat);
var yOutput = createVariable({prefix:" Y"}, xyzFormat);
var zOutput = createVariable({prefix:" Z"}, xyzFormat);
var fOutput = createVariable({prefix:" F"}, feedFormat);

// Circular outputs
var	iOutput	=	createReferenceVariable({prefix:" I"},	xyzFormat);
var	jOutput	=	createReferenceVariable({prefix:" J"},	xyzFormat);
var	kOutput	=	createReferenceVariable({prefix:" K"},	xyzFormat);

// Arc support variables
minimumChordLength	=	spatial(0.01,	MM);
minimumCircularRadius	=	spatial(1.0,	MM);	// Same values disables IJK
maximumCircularRadius	=	spatial(1.5,	MM);	// Same values disables IJK
minimumCircularSweep	=	toRad(0.01);
maximumCircularSweep	=	toRad(180);
allowHelicalMoves	=	false;
allowedCircularPlanes	=	undefined;

// Misc variables
var powerState = false;
var cutterOn;
var currentXPos = 0;
var currentYPos = 0;

// Called in every new gcode file
function onOpen() {
  // See onSection
  return;
}

// Called at end of gcode file
function onClose() {
  writeln("M400");
  writeln(properties.cutterOff);

  writeln("G0 Z50" + fOutput.format(properties.travelSpeedZ)); // Raise cut head.
  writeln("G0 X0 Y0" + fOutput.format(properties._travelSpeedXY)); // Go to XY origin
  
  // End message to LCD
  writeln("M117 Job end");
  return;
}

// Called in every section
function onSection() {

  // Write Start gcode of the documment (after the "onParameters" with the global info)
  if(isFirstSection()) {
    writeln("");
    writeln("G90"); // Set to Absolute Positioning
    writeln("G21"); // Set Units to Millimeters
	  writeln("G28 Z");	// Z is at 4 after homing
    writeln("G92 X0 Y0 Z4"); // Set origin to initial position
    writeln("");
  }

  // Cutter mode used for different thc voltages
  cutterOn = properties.cutterOn + " V" + properties._thcVoltage + " D" + properties._delay + " H" + properties._cutHeight + " I" + properties._initialHeight + " T" + properties._thcHeightIncrement;
  writeComment(sectionComment + " - Plasma - Cutting mode: " + getParameter("operation:cuttingMode"));

  // Print min/max boundaries for each section
  vectorX = new Vector(1,0,0);
  vectorY = new Vector(0,1,0);
  writeComment("X Min: " + xyzFormat.format(currentSection.getGlobalRange(vectorX).getMinimum()) + " - X Max: " + xyzFormat.format(currentSection.getGlobalRange(vectorX).getMaximum()));
  writeComment("Y Min: " + xyzFormat.format(currentSection.getGlobalRange(vectorY).getMinimum()) + " - Y Max: " + xyzFormat.format(currentSection.getGlobalRange(vectorY).getMaximum()));
  writeComment("Z Min: " + xyzFormat.format(currentSection.getGlobalZRange().getMinimum()) + " - Z Max: " + xyzFormat.format(currentSection.getGlobalZRange().getMaximum()));

  // Display section name in LCD
  writeln("M400");
  writeln("M117 " + sectionComment);
   return;
}

// Called in every section end
function onSectionEnd() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
  fOutput.reset();
  writeln("");
  return;
}

// Rapid movements
function onRapid(x, y, z)	{
  rapidMovements(x, y, z);
  return;
}

// Feed movements
function onLinear(x, y, z, feed)	{
  linearMovements(x, y, z, feed);
  return;
}

function onCircular(clockwise, cx, cy, cz, x,	y, z, feed)	{
  circularMovements(clockwise, cx, cy, cz, x,	y, z, feed);
  return;
}

// Called on waterjet/plasma/laser cuts
function onPower(power) {
  if(power != powerState) {
    if(power) {
	  writeln("M400");
	  writeln("G28 Z");	// Z is at 4 after homing
      writeln(cutterOn);
    } else {
	  writeln("M400");
      writeln(properties.cutterOff);
    }
    powerState = power;
  }
  return;
}

// Called on Dwell Manual NC invocation
function onDwell(seconds) {
  writeComment("Dwell");
  writeln("G4 S" + seconds);
  writeln("");
}

// Called with every parameter in the document/section
function onParameter(name, value) {

  // Write gcode initial info
  // Product version
  if(name == "generated-by") {
    writeComment(value);
    writeComment("Posts processor: " + FileSystem.getFilename(getConfigurationPath()));
  }
  // Date
  if(name == "generated-at") writeComment("Gcode generated: " + value + " GMT");
  // Document
  if(name == "document-path") writeComment("Document: " + value);
  // Setup
  if(name == "job-description") writeComment("Setup: " + value);

  // Get section comment
  if(name == "operation-comment") sectionComment = value;

  return;
}

// Output a comment
function writeComment(text) {
  writeln(";" + String(text).replace(/[\(\)]/g, ""));
  return;
}

// Rapid movements with G1 and differentiated travel speeds for XY and Z
function rapidMovements(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);

  if(x || y) {
    f = fOutput.format(properties._travelSpeedXY);
    fOutput.reset();
    writeln("G1" + x + y + f);
    currentXPos = _x;
    currentYPos = _y;
  }
  return;
}

// Linear feed movements
// Divide G1 moves into properties._thcStepSize
function linearMovements(_x, _y, _z, feed) {

  // Uncomment these two lines to bypass the divitions
  writeln("G1" + xOutput.format(_x) + yOutput.format(_y) + fOutput.format(properties._feedSpeed));
  return;

  if (_x || _y) {
    var distanceX = _x - currentXPos;
    var distanceY = _y - currentYPos;
    var distance = Math.sqrt(Math.pow(distanceX, 2) + Math.pow(distanceY, 2));

    if (distance > properties._thcStepSize * 11) {  // Don't divide already small movements
  
      // Note, truncates the distance
      var numberOfSteps = Math.floor(distance / properties._thcStepSize);
      var stepSizeX = distanceX / numberOfSteps;
      var stepSizeY = distanceY / numberOfSteps;
  
      for (var i = 0; i < numberOfSteps; ++i) {
          var nextXPos = currentXPos + (i+1) * stepSizeX;
          var nextYPos = currentYPos + (i+1) * stepSizeY;
          writeln("G1" + xOutput.format(nextXPos) + yOutput.format(nextYPos) + fOutput.format(properties._feedSpeed));
      }

      // Take care of any remainders
      // If any of these are non-zero, write an extra writeln to get to the corrent endpoint
      var remainingDistanceX = distanceX - (stepSizeX * numberOfSteps);
      var remainingDistanceY = distanceY - (stepSizeY * numberOfSteps);
    
      if ((remainingDistanceX) || (remainingDistanceY)){
          writeln("G1" + xOutput.format(remainingDistanceX) + yOutput.format(remainingDistanceY) + fOutput.format(properties._feedSpeed));
      }
    }
    else writeln("G1" + xOutput.format(_x) + yOutput.format(_y) + fOutput.format(properties._feedSpeed));
  }

  currentXPos = _x;
  currentYPos = _y;
  
  return;
}

// Circular movements
function circularMovements(_clockwise, _cx, _cy, _cz, _x, _y, _z, feed) {
  // Marlin supports arcs only on XY plane
  switch (getCircularPlane()) {
  case PLANE_XY:
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    var f = fOutput.format(properties._feedSpeed);
    var start	=	getCurrentPosition();
    var i = iOutput.format(_cx - start.x, 0);
    var j = jOutput.format(_cy - start.y, 0);

    if(_clockwise) {
      writeln("G2" + x + y + i + j + f);
    } else {
      writeln("G3" + x + y + i + j + f);
    }
    currentXPos = _x;
    currentYPos = _y;
    break;
  default:
    linearize(tolerance);
  }
  return;
}
