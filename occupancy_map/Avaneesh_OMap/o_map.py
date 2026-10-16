import pandas as pd
import numpy as np
import math
import matplotlib.pyplot as plt

### OCCUPANCY MAP implementation

UNKNOWN = 0.5
FULL = 1
EMPTY = 0

RESOLUTION = 2

LIDAR_PATH = 'data/lidar_spin_scan.csv'

# index by shape, e.g. TEST_CASES[0]['simplified'] or TEST_CASES[1]['lidar']
TEST_CASES = [
    {
        'name': 'rectangle',
        'simplified': 'data/test_cases/rectangle_simplified.csv',
        'servo': 'data/test_cases/rectangle_servo_log.csv',
        'lidar': 'data/test_cases/rectangle_tf_luna_raw.csv',
    },
    {
        'name': 'circle',
        'simplified': 'data/test_cases/circle_simplified.csv',
        'servo': 'data/test_cases/circle_servo_log.csv',
        'lidar': 'data/test_cases/circle_tf_luna_raw.csv',
    },
    {
        'name': 'zigzag',
        'simplified': 'data/test_cases/zigzag_simplified.csv',
        'servo': 'data/test_cases/zigzag_servo_log.csv',
        'lidar': 'data/test_cases/zigzag_tf_luna_raw.csv',
    },
]


def print_o_map(occupancy_map):
    for row in occupancy_map:
        print(row)

def create_df(servo_path, lidar_path):
    PRECISION = 3
    ORIGINAL_BASE = 16
    RAW_MULT_CONSTANT = 256

    servo_log = pd.read_csv(servo_path)
    raw_lidar_data = pd.read_csv(lidar_path)
    
    # round all timestamps in original df
    for idx, ts in enumerate(raw_lidar_data["timestamp_s"]):
        raw_lidar_data.loc[idx, "timestamp_s"] = round(ts, PRECISION)

    lidar_data = pd.DataFrame(columns = ["timestamp_s", "avg_dist", "avg_strength", "servo_angle_deg"])

    # go through each row in original df
    # transfer the content in the original df to the new df, while interpreting the values in the new df
    for idx, row in enumerate(raw_lidar_data.itertuples()):
        new_ts = row.timestamp_s
        new_dist = int(row.byte2, ORIGINAL_BASE) + int(row.byte3, ORIGINAL_BASE) * RAW_MULT_CONSTANT
        new_strength = int(row.byte4, ORIGINAL_BASE) + int(row.byte5, ORIGINAL_BASE) * RAW_MULT_CONSTANT
        lidar_data.loc[len(lidar_data)] = [new_ts, new_dist, new_strength, np.nan]

    lidar_data = lidar_data.groupby('timestamp_s').mean()

    for idx, row in enumerate(servo_log.itertuples()):
        cur_ts = round(row.timestamp_s, PRECISION)

        # get row in lidar_data with this ts
        lidar_data.loc[cur_ts, "servo_angle_deg"] = row.servo_angle_deg

    # fill gaps between timestamps for servo_angles
    lidar_data['servo_angle_deg'] = lidar_data['servo_angle_deg'].ffill()

    # ignore NaN values for distance
    return lidar_data.dropna(subset = ["avg_dist"])

def polar_to_cartesian(lidar_data):
    xs = []
    ys = []
    for row in lidar_data.itertuples():
        angle_deg = row.servo_angle_deg
        angle_rad = angle_deg * math.pi / 180

        xs.append(row.avg_dist * np.cos(angle_rad))
        ys.append(row.avg_dist * np.sin(angle_rad))
   

    # ground sensor at (0, 0)
    xs += [0]
    ys += [0]

    return xs, ys

def create_grid(xs, ys):    
    min_x = int(min(xs)) # round down
    max_x = math.ceil(max(xs)) # round up

    min_y = int(min(ys))
    max_y = math.ceil(max(ys))

    # all are UNKNOWN squares
    grid = np.full((
        math.ceil((max_x - min_x) / RESOLUTION),
        math.ceil((max_y - min_y) / RESOLUTION)
    ), UNKNOWN)

    full_coords = set()
    # populate our occupancy map with objects, from LiDAR data
    for x, y in zip(xs, ys):
        if (x == 0 and y == 0):
            continue

        # shift lidar data coords to fit with our numpy array indexing (minimum coord at 0)
        cur_x = int((x - min_x) / RESOLUTION)
        cur_y = int((y - min_y) / RESOLUTION)
        full_coords.add((cur_x, cur_y))

    return grid, full_coords, min_x, min_y



def in_bounds(x, y, grid):
    return x < len(grid) and x >= 0 and y < len(grid[0]) and y >= 0


# c_x/c_y are the center coordinates --> coordinates of the lidar
def bresenham(grid, full_coords, c_x, c_y):
    # our sensor is at the center of the grid
    for pair in full_coords:
        x, y = pair

        # calculate distance from the goal
        dx = abs(x - c_x)
        dy = abs(y - c_y)

        # set step direction
        step_x = 1
        if (x < c_x):
            step_x = -1
        step_y = 1
        if (y < c_y):
            step_y = -1      

        # manifest this distance into an error value
        err = dx - dy
        cur_x = c_x
        cur_y = c_y

        # goal of the loop: minimize err, since this represents the ideal line
        # essentially draw out a line until you hit a coordinate in full_coords (non-empty coordinate)
        while (not (cur_x == x and cur_y == y) and in_bounds(cur_x, cur_y, grid)):
            grid[cur_x][cur_y] = EMPTY
            temp_err = 2 * err

            # adjust x
            # If the error is too low (below -dy), we've moved in the x direction too many times,
            # and we need to balance it by moving in the y direction

            if (temp_err > -dy):
                cur_x += step_x
                err -= dy          

            # adjust y
            if (temp_err < dx):
                cur_y += step_y
                err += dx
    
    # set FULL
    for x, y in full_coords:
        if in_bounds(x, y, grid):
            grid[x][y] = FULL
    return grid



def visualize(data):
    plt.imshow(data, origin='lower', cmap='viridis')
    plt.colorbar() # Adds a legend for the color scale
    plt.show()

def from_raw_lidar(servo_path='data/servo_log.csv', lidar_path='data/tf_luna_raw.csv'):
    lidar_data = create_df(servo_path, lidar_path)
    xs, ys = polar_to_cartesian(lidar_data)
    occupancy_map, full_coords, min_x, min_y = create_grid(xs, ys)
    # lidar is at (0, 0), but we convert it to be able to index the array
    lidar_x = int((0 - min_x) / RESOLUTION)
    lidar_y = int((0 - min_y) / RESOLUTION)

    print(f"LIDAR is at {(lidar_x, lidar_y)}")
    occupancy_map = bresenham(occupancy_map, full_coords, lidar_x, lidar_y)
    visualize(occupancy_map.T)

def from_simplified(lidar_path=LIDAR_PATH):
    lidar_data = pd.read_csv(lidar_path)
    lidar_data.rename(columns={'angle_deg': 'servo_angle_deg', 'distance_m': 'avg_dist'}, inplace=True)

    # convert the lidar data to cartesian coordinates assuming the sensor sits at (0, 0)
    xs, ys = polar_to_cartesian(lidar_data)

    # create the grid bounding box given the xs and ys.
    # gets the bounding box extrema (max/min x/y), initially mark all as unknown
    occupancy_map, full_coords, min_x, min_y = create_grid(xs, ys)

    # lidar is at (0, 0), but we convert it to be able to index the array
    lidar_x = int((0 - min_x) / RESOLUTION)
    lidar_y = int((0 - min_y) / RESOLUTION)

    print(f"LIDAR is at {(lidar_x, lidar_y)}")

    # apply bresenham's algorithm
    occupancy_map = bresenham(occupancy_map, full_coords, lidar_x, lidar_y).T
    visualize(occupancy_map)


if __name__ == '__main__':
    from_raw_lidar(TEST_CASES[2]['servo'], TEST_CASES[2]['lidar'])
    # from_simplified()
