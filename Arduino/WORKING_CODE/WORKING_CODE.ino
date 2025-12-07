const int DEADZONE = 80;  // Ignore tiny joystick noise
int SENSOR_PIN = A4; // center pin of the potentiometer
int RPWM_Output = 5; // Arduino PWM output pin 5; connect to IBT-2 pin 1 (RPWM)
int LPWM_Output = 6; // Arduino PWM output pin 6; connect to IBT-2 pin 2 (LPWM)

void setup()
{
  pinMode(RPWM_Output, OUTPUT);
  pinMode(LPWM_Output, OUTPUT);
}

void loop()
{
  int sensorValue = analogRead(SENSOR_PIN);

  // CENTER → DEADZONE → MOTOR OFF
  if (abs(sensorValue - 511) < DEADZONE) {
    analogWrite(RPWM_Output, 0);
    analogWrite(LPWM_Output, 0);
  }

  // REVERSE
  else if (sensorValue < 512)
  {
    int reversePWM = -(sensorValue - 511) / 2;
    analogWrite(LPWM_Output, 0);
    analogWrite(RPWM_Output, reversePWM);
  }

  // FORWARD
  else
  {
    int forwardPWM = (sensorValue - 512) / 2;
    analogWrite(LPWM_Output, forwardPWM);
    analogWrite(RPWM_Output, 0);
  }
}