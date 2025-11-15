// --- Pin Definitions ---
// Joystick
#define VRX A5
#define VRY A4

// Motor A (Left)
#define IN1 10
#define IN2 9
#define ENA 11

// Motor B (Right)
#define IN3 5
#define IN4 4
#define ENB 3

// --- Constants ---
const int DEADZONE = 80;  // Ignore tiny joystick noise

//===================================================================
void setup() {
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);
  pinMode(ENB, OUTPUT);
  pinMode(VRX, INPUT);
  pinMode(VRY, INPUT);
}
//===================================================================

void loop() {
  // Read joystick values (center them around 0)
  int xVal = analogRead(VRX) - 511;
  int yVal = analogRead(VRY) - 511;

  // APPLY DEADZONE so small movements do nothing
  if (abs(xVal) < DEADZONE) xVal = 0;
  if (abs(yVal) < DEADZONE) yVal = 0;

  // Stronger steering: amplify X slightly (steering priority)
  xVal *= 1.2;  // <-- makes turning more aggressive

  // Mix joystick values for differential steering
  int leftMotorSpeed = constrain(yVal + xVal, -511, 511);
  int rightMotorSpeed = constrain(yVal - xVal, -511, 511);

  // --- LEFT MOTOR ---
  if (leftMotorSpeed > 0) {
    digitalWrite(IN1, HIGH);
    digitalWrite(IN2, LOW);
  } else if (leftMotorSpeed < 0) {
    digitalWrite(IN1, LOW);
    digitalWrite(IN2, HIGH);
  } else {
    digitalWrite(IN1, LOW);
    digitalWrite(IN2, LOW);
  }
  // Map from -511/511 range to 0-255 PWM range
  analogWrite(ENA, abs(leftMotorSpeed) / 2);

  // --- RIGHT MOTOR ---
  if (rightMotorSpeed > 0) {
    digitalWrite(IN3, HIGH);
    digitalWrite(IN4, LOW);
  } else if (rightMotorSpeed < 0) {
    digitalWrite(IN3, LOW);
    digitalWrite(IN4, HIGH);
  } else {
    digitalWrite(IN3, LOW);
    digitalWrite(IN4, LOW);
  }
  // Map from -511/511 range to 0-255 PWM range
  analogWrite(ENB, abs(rightMotorSpeed) / 2);

  delay(10);
}

//NEW ADDIONS SHOULD ONLY BE ON AARAV BRANCH