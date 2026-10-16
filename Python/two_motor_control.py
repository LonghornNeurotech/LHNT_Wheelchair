"""
A joystick drives two motors (Sketch 2) -- Python version of the .ino sketch.

The Y axis sets forward and back. The X axis steers. Mixing the two gives
each motor its own speed:  left = y + x,  right = y - x.

Python runs on your computer (or a Raspberry Pi) and talks to the Arduino
over USB using the Firmata protocol.

One-time setup:
  1. In the Arduino IDE: File > Examples > Firmata > StandardFirmata,
     then upload it to the board.
  2. On your computer:  pip install pyfirmata2
  3. Run:               python two_motor_control.py

Wiring is unchanged from the .ino sketch.
"""

import time

# --- Pin Definitions ---
# Joystick
VRX = 5              # A5
VRY = 4              # A4

# Motor A (Left)
IN1 = 10
IN2 = 9
ENA = 11

# Motor B (Right)
IN3 = 5
IN4 = 4
ENB = 3

# --- Constants ---
DEADZONE = 80        # Ignore tiny joystick noise

PORT = None          # None = auto-detect. Or set e.g. "COM3" or "/dev/ttyACM0"
LOOP_DELAY = 0.01    # seconds between updates, same as delay(10)


def constrain(value, low, high):
    return max(low, min(high, value))


def mix(x_reading, y_reading):
    """Turn two 0-1023 joystick readings into (left_speed, right_speed).

    Each speed runs from -511 (full reverse) to 511 (full forward).
    """
    # Center the readings around 0
    x_val = x_reading - 511
    y_val = y_reading - 511

    # APPLY DEADZONE so small movements do nothing
    if abs(x_val) < DEADZONE:
        x_val = 0
    if abs(y_val) < DEADZONE:
        y_val = 0

    # Stronger steering: amplify X by 1.2 (steering priority).
    # Written as 12/10 so whole numbers stay exact; int() drops the
    # fraction the same way the Arduino's int does.
    x_val = int(x_val * 12 / 10)

    # Mix joystick values for differential steering
    left_speed = constrain(y_val + x_val, -511, 511)
    right_speed = constrain(y_val - x_val, -511, 511)
    return left_speed, right_speed


def motor_signals(speed):
    """Turn one motor's speed (-511 to 511) into (in_a, in_b, pwm).

    in_a and in_b are the two direction pins (1 = HIGH, 0 = LOW).
    pwm is 0-255 for the enable pin.
    """
    if speed > 0:
        in_a, in_b = 1, 0          # forward
    elif speed < 0:
        in_a, in_b = 0, 1          # reverse
    else:
        in_a, in_b = 0, 0          # stopped

    # Map from -511/511 range to 0-255 PWM range
    return in_a, in_b, abs(speed) // 2


def connect():
    """Connect to the Arduino and set up the motor pins.

    Returns (board, drive), where drive(left_speed, right_speed) sends
    the direction and PWM signals for both motors.
    """
    from pyfirmata2 import Arduino

    board = Arduino(PORT or Arduino.AUTODETECT)

    # setup(): same roles as pinMode in the sketch
    left = (board.get_pin(f"d:{IN1}:o"), board.get_pin(f"d:{IN2}:o"),
            board.get_pin(f"d:{ENA}:p"))
    right = (board.get_pin(f"d:{IN3}:o"), board.get_pin(f"d:{IN4}:o"),
             board.get_pin(f"d:{ENB}:p"))

    def drive(left_speed, right_speed):
        for speed, (pin_a, pin_b, enable) in ((left_speed, left),
                                              (right_speed, right)):
            in_a, in_b, pwm = motor_signals(speed)
            pin_a.write(in_a)
            pin_b.write(in_b)
            enable.write(pwm / 255)   # Firmata PWM takes 0.0-1.0

    return board, drive


def main():
    board, drive = connect()
    board.samplingOn(10)  # report analog readings every 10 ms

    # pyfirmata2 delivers analog readings through callbacks, so keep the
    # most recent ones here for the loop to use.
    latest = {"x": None, "y": None}   # 0.0-1.0, or None before first sample

    def on_x(value):
        latest["x"] = value

    def on_y(value):
        latest["y"] = value

    board.get_pin(f"a:{VRX}:i").register_callback(on_x)
    board.get_pin(f"a:{VRY}:i").register_callback(on_y)

    try:
        # loop()
        while True:
            if latest["x"] is None or latest["y"] is None:
                drive(0, 0)
            else:
                x_reading = round(latest["x"] * 1023)  # back to 0-1023
                y_reading = round(latest["y"] * 1023)
                drive(*mix(x_reading, y_reading))

            time.sleep(LOOP_DELAY)

    except KeyboardInterrupt:
        pass
    finally:
        # Always stop both motors when the script ends
        drive(0, 0)
        board.exit()


if __name__ == "__main__":
    main()
