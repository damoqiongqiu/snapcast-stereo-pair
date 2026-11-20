#!/usr/bin/env python3
import array
import math
import os
import sys

SCALE = 8388608
RATE = 48000
WINDOW = 8192


def load(path):
    samples = array.array("i")
    size = os.path.getsize(path)
    with open(path, "rb") as source:
        samples.fromfile(source, size // 4)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def rms(samples):
    return math.sqrt(sum(value * value for value in samples) / len(samples))


def active_window(samples):
    size = min(WINDOW, len(samples))
    if size == 0:
        raise SystemExit("signal is silent")
    energy = sum(value * value for value in samples[:size])
    best_energy = energy
    best_start = 0
    for index in range(size, len(samples)):
        energy += samples[index] * samples[index]
        energy -= samples[index - size] * samples[index - size]
        if energy > best_energy:
            best_energy = energy
            best_start = index - size + 1
    if best_energy == 0:
        raise SystemExit("signal is silent")
    return samples[best_start : best_start + size]


def correlation_offset(left, right, max_lag):
    left = active_window(left)
    right = active_window(right)
    best_lag = 0
    best_score = float("-inf")
    for lag in range(-max_lag, max_lag + 1):
        start_left = max(0, -lag)
        start_right = max(0, lag)
        count = min(len(left) - start_left, len(right) - start_right)
        if count <= 0:
            continue
        score = sum(
            left[start_left + index] * right[start_right + index]
            for index in range(count)
        )
        if score > best_score:
            best_score = score
            best_lag = lag
    return best_lag


if len(sys.argv) != 3:
    raise SystemExit(f"usage: {sys.argv[0]} LEFT_RAW RIGHT_RAW")

left = load(sys.argv[1])
right = load(sys.argv[2])
common_frames = min(len(left), len(right))
length_delta_ms = (len(left) - len(right)) * 1000 / RATE

max_lag = RATE // 100
lag = correlation_offset(left, right, max_lag)
peak = max(max(abs(value) for value in left), max(abs(value) for value in right))

print(f"samples={len(left)}")
left_level = rms(left)
right_level = rms(right)
left_db = 20 * math.log10(left_level / SCALE) if left_level else float("-inf")
right_db = 20 * math.log10(right_level / SCALE) if right_level else float("-inf")
peak_db = 20 * math.log10(peak / SCALE) if peak else float("-inf")
print(f"left_rms_dbfs={left_db:.2f}")
print(f"right_rms_dbfs={right_db:.2f}")
print(f"peak_dbfs={peak_db:.2f}")
print(f"relative_offset_ms={abs(lag) * 1000 / RATE:.4f}")
print(f"length_delta_ms={length_delta_ms:.4f}")
print(f"channels_differ={left[:common_frames] != right[:common_frames]}")
