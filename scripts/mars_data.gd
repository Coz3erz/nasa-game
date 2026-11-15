# CHANGELOG (2026-11-15): Offline Mars constants feed calibrated solar output; retain requested nominal gravity and exact gameplay sol.
# Source: https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html
class_name MarsData
extends RefCounted

const SOL_SECONDS: float = 88775.244
const SOLAR_IRRADIANCE_W_M2: float = 586.2
const EARTH_IRRADIANCE_W_M2: float = 1361.0
# Requested nominal gravity. NASA currently lists mean surface gravity as 3.73 m/s2.
const GRAVITY_M_S2: float = 3.71
const PRESSURE_KPA: float = 0.636
const AXIAL_TILT_DEG: float = 25.19
const SOLAR_EFFICIENCY_VS_EARTH: float = SOLAR_IRRADIANCE_W_M2 / EARTH_IRRADIANCE_W_M2
