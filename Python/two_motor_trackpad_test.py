"""
Trackpad tester for two_motor_control.py

Your trackpad stands in for the joystick. Move the pointer around the
square pad: left/right is the X axis (steering), up/down is the Y axis
(up = forward). The window shows what mix() and motor_signals() from
two_motor_control.py would send to each motor.

Keep this file in the same folder as two_motor_control.py, then run:

    python two_motor_trackpad_test.py            # on screen only
    python two_motor_trackpad_test.py --board    # also drive the real motors

Moving the pointer out of the window snaps back to center, like letting go
of the joystick, so both motors stop.
"""

import sys
import tkinter as tk

try:
    from two_motor_control import (
        mix, motor_signals, connect, DEADZONE,
        IN1, IN2, ENA, IN3, IN4, ENB,
    )
except ImportError:
    sys.exit("Put this file in the same folder as two_motor_control.py.")

WIDTH, HEIGHT = 780, 420
PAD_LEFT, PAD_TOP, PAD_SIZE = 40, 70, 300     # the square joystick pad
PANEL = 400                                   # left edge of the readouts
BAR_LEFT, BAR_RIGHT = PANEL + 110, WIDTH - 140
CENTER = 511


def pointer_to_readings(px, py):
    """Pointer position in the window -> (x_reading, y_reading), 0-1023.

    Left edge of the pad is X = 0, right edge is X = 1023.
    Bottom edge is Y = 0, top edge is Y = 1023 (up = forward).
    """
    fx = (px - PAD_LEFT) / PAD_SIZE
    fy = (PAD_TOP + PAD_SIZE - py) / PAD_SIZE
    x_reading = max(0, min(1023, round(fx * 1023)))
    y_reading = max(0, min(1023, round(fy * 1023)))
    return x_reading, y_reading


def readings_to_pointer(x_reading, y_reading):
    px = PAD_LEFT + x_reading / 1023 * PAD_SIZE
    py = PAD_TOP + PAD_SIZE - y_reading / 1023 * PAD_SIZE
    return px, py


def describe(left_speed, right_speed):
    """Plain-words result, like the table in the walkthrough."""
    if left_speed == 0 and right_speed == 0:
        return "Stopped"
    if left_speed * right_speed < 0:
        side = "right" if left_speed > 0 else "left"
        return f"Spins {side} in place"
    if left_speed == right_speed:
        return "Drives straight" if left_speed > 0 else "Backs up"
    if left_speed >= 0 and right_speed >= 0:
        return "Curves right" if left_speed > right_speed else "Curves left"
    return "Backs up while turning"


class Tester:
    def __init__(self, root, use_board=False):
        self.root = root
        self.board = self.drive = None
        self.last_sent = None
        if use_board:
            self.board, self.drive = connect()

        mode = "driving the real motors" if use_board else "screen only"
        root.title(f"Two-motor trackpad tester ({mode})")
        root.resizable(False, False)

        c = self.canvas = tk.Canvas(root, width=WIDTH, height=HEIGHT,
                                    bg="white", highlightthickness=0)
        c.pack()

        # Joystick pad, with the deadzone bands shaded
        right, bottom = PAD_LEFT + PAD_SIZE, PAD_TOP + PAD_SIZE
        c.create_rectangle(PAD_LEFT, PAD_TOP, right, bottom,
                           fill="#eeeeee", outline="#bbbbbb")
        lo_x, lo_y = readings_to_pointer(CENTER - DEADZONE + 1,
                                         CENTER - DEADZONE + 1)
        hi_x, hi_y = readings_to_pointer(CENTER + DEADZONE - 1,
                                         CENTER + DEADZONE - 1)
        c.create_rectangle(lo_x, PAD_TOP, hi_x, bottom,
                           fill="#d5d5d5", outline="")
        c.create_rectangle(PAD_LEFT, hi_y, right, lo_y,
                           fill="#d5d5d5", outline="")
        mid = PAD_LEFT + PAD_SIZE / 2
        c.create_text(mid, 30, font=("Helvetica", 13), fill="#444",
                      text="Move the pointer around the pad")
        c.create_text(mid, PAD_TOP - 12, text="forward", fill="#666")
        c.create_text(mid, bottom + 14, text="back", fill="#666")
        c.create_text(PAD_LEFT - 6, PAD_TOP + PAD_SIZE / 2, text="left",
                      fill="#666", angle=90, anchor="s")
        c.create_text(right + 6, PAD_TOP + PAD_SIZE / 2, text="right",
                      fill="#666", angle=270, anchor="s")
        c.create_text(mid, bottom + 34, fill="#888",
                      text="shaded bands = deadzone")
        self.marker = c.create_oval(0, 0, 0, 0, fill="#222222", outline="")

        # Readouts
        self.result = c.create_text(PANEL, 85, anchor="w",
                                    font=("Helvetica", 20, "bold"))
        self.readings = c.create_text(PANEL, 118, anchor="w",
                                      font=("Courier", 13), fill="#444")
        self.left = self.make_motor(165, "LEFT MOTOR", ENA, IN1, IN2)
        self.right = self.make_motor(285, "RIGHT MOTOR", ENB, IN3, IN4)

        c.bind("<Motion>", lambda e: self.update(
            *pointer_to_readings(e.x, e.y)))
        c.bind("<Leave>", lambda e: self.update(CENTER, CENTER))
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.update(CENTER, CENTER)

    def make_motor(self, y, name, enable_pin, pin_a, pin_b):
        """Draw one motor's readout block. Returns its canvas items."""
        c = self.canvas
        c.create_text(PANEL, y, text=name, anchor="w",
                      font=("Helvetica", 13, "bold"))
        direction = c.create_text(PANEL + 150, y, anchor="w",
                                  font=("Helvetica", 13, "bold"))
        bar_y = y + 32
        c.create_text(PANEL, bar_y, anchor="w",
                      text=f"PWM (pin {enable_pin})")
        c.create_rectangle(BAR_LEFT, bar_y - 9, BAR_RIGHT, bar_y + 9,
                           fill="#eeeeee", outline="")
        bar = c.create_rectangle(BAR_LEFT, bar_y - 9, BAR_LEFT, bar_y + 9,
                                 outline="")
        number = c.create_text(BAR_RIGHT + 10, bar_y, anchor="w",
                               font=("Courier", 13))
        pins = c.create_text(PANEL, y + 62, anchor="w",
                             font=("Courier", 12), fill="#444")
        return {"direction": direction, "bar": bar, "number": number,
                "pins": pins, "bar_y": bar_y, "pin_a": pin_a, "pin_b": pin_b}

    def show_motor(self, items, speed):
        in_a, in_b, pwm = motor_signals(speed)   # <-- the code under test

        if speed > 0:
            word, color = "FORWARD", "#2e7d32"
        elif speed < 0:
            word, color = "REVERSE", "#c0392b"
        else:
            word, color = "STOPPED", "#555555"

        c = self.canvas
        y = items["bar_y"]
        bar_right = BAR_LEFT + pwm / 255 * (BAR_RIGHT - BAR_LEFT)
        c.itemconfig(items["direction"], text=word, fill=color)
        c.coords(items["bar"], BAR_LEFT, y - 9, bar_right, y + 9)
        c.itemconfig(items["bar"], fill=color)
        c.itemconfig(items["number"], text=f"{pwm:3d} / 255")
        level = {1: "HIGH", 0: "LOW "}
        c.itemconfig(items["pins"], text=(
            f"pin {items['pin_a']}: {level[in_a]}   "
            f"pin {items['pin_b']}: {level[in_b]}"))

    def update(self, x_reading, y_reading):
        left_speed, right_speed = mix(x_reading, y_reading)  # <-- under test

        c = self.canvas
        px, py = readings_to_pointer(x_reading, y_reading)
        c.coords(self.marker, px - 9, py - 9, px + 9, py + 9)
        c.itemconfig(self.result, text=describe(left_speed, right_speed))
        c.itemconfig(self.readings,
                     text=f"X (A5): {x_reading:4d}    Y (A4): {y_reading:4d}")
        self.show_motor(self.left, left_speed)
        self.show_motor(self.right, right_speed)

        self.send(left_speed, right_speed)

    def send(self, left_speed, right_speed):
        """Write to the real motor driver, only when the speeds change."""
        if self.drive is None or (left_speed, right_speed) == self.last_sent:
            return
        self.drive(left_speed, right_speed)
        self.last_sent = (left_speed, right_speed)

    def close(self):
        """Stop both motors before the window goes away."""
        if self.board is not None:
            self.send(0, 0)
            self.board.exit()
            self.board = self.drive = None
        self.root.destroy()


def main():
    root = tk.Tk()
    tester = Tester(root, use_board="--board" in sys.argv)
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
    finally:
        if tester.board is not None:
            tester.close()


if __name__ == "__main__":
    main()
