"""
Generates synthetic LiDAR scans of known shapes, in both data formats
o_map.py understands:

  - "simplified": angle_deg,distance_m   (consumed by from_simplified)
  - "raw":        servo_log.csv + tf_luna_raw.csv (consumed by from_raw_lidar)

All shapes assume a 180-degree sweep (0 to 180 inclusive) with the sensor
fixed at the world origin (0, 0), matching the real hardware's convention
(servo_log.csv sweeps 0-180) and the rest of o_map.py's assumption that the
upper half-plane (y >= 0) is what gets scanned.

Output goes to data/test_cases/<shape>_simplified.csv and
data/test_cases/<shape>_servo_log.csv / <shape>_tf_luna_raw.csv.
"""

import math
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), 'data', 'test_cases')
ANGLE_STEP_DEG = 1
DT = 0.004  # seconds between samples, matches the ~4ms cadence in the sample data
STRENGTH = 800  # arbitrary, fixed TF-Luna signal-strength reading


def rectangle_profile(theta_deg, half_width=2.0, height=3.0):
    """
    Sensor sits at the midpoint of the room's south wall (an edge of the
    rectangle, not its center). Room spans x in [-half_width, half_width],
    y in [0, height].
    """
    theta = math.radians(theta_deg)
    cos_t, sin_t = math.cos(theta), math.sin(theta)

    t_y = height / sin_t if sin_t > 1e-9 else float('inf')
    if cos_t > 1e-9:
        t_x = half_width / cos_t
    elif cos_t < -1e-9:
        t_x = -half_width / cos_t
    else:
        t_x = float('inf')

    return min(t_x, t_y)


def circle_profile(theta_deg, radius=2.5):
    """Sensor at the center of a circular room; wall is a constant radius away."""
    return radius


def zigzag_profile(theta_deg, period_deg=20.0, d_min=1.0, d_max=3.0):
    """Triangle wave in distance vs. angle -> a jagged sawtooth wall."""
    phase = (theta_deg % period_deg) / period_deg
    tri = 1.0 - abs(2.0 * phase - 1.0)  # 0 -> 1 -> 0 over one period
    return d_min + (d_max - d_min) * tri


SHAPES = {
    'rectangle': rectangle_profile,
    'circle': circle_profile,
    'zigzag': zigzag_profile,
}


def angles():
    n = int(180 / ANGLE_STEP_DEG)
    return [i * ANGLE_STEP_DEG for i in range(n + 1)]


def write_simplified(name, profile_fn):
    path = os.path.join(OUT_DIR, f'{name}_simplified.csv')
    with open(path, 'w') as f:
        f.write('angle_deg,distance_m\n')
        for theta in angles():
            dist_m = profile_fn(theta)
            f.write(f'{theta},{dist_m:.4f}\n')
    print(f'wrote {path}')


def write_raw(name, profile_fn):
    servo_path = os.path.join(OUT_DIR, f'{name}_servo_log.csv')
    lidar_path = os.path.join(OUT_DIR, f'{name}_tf_luna_raw.csv')

    with open(servo_path, 'w') as servo_f, open(lidar_path, 'w') as lidar_f:
        servo_f.write('timestamp_s,servo_angle_deg\n')
        lidar_f.write('timestamp_s,byte0,byte1,byte2,byte3,byte4,byte5,byte6,byte7,byte8\n')

        for idx, theta in enumerate(angles()):
            ts = round(idx * DT, 3)
            dist_cm = int(round(profile_fn(theta) * 100))

            servo_f.write(f'{ts:.3f},{float(theta)}\n')

            byte2 = dist_cm % 256
            byte3 = dist_cm // 256
            byte4 = STRENGTH % 256
            byte5 = STRENGTH // 256
            lidar_f.write(
                f'{ts:.3f},0x59,0x59,'
                f'0x{byte2:02X},0x{byte3:02X},'
                f'0x{byte4:02X},0x{byte5:02X},'
                f'0x62,0x00,0x8D\n'
            )
    print(f'wrote {servo_path}')
    print(f'wrote {lidar_path}')


if __name__ == '__main__':
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, profile_fn in SHAPES.items():
        write_simplified(name, profile_fn)
        write_raw(name, profile_fn)
