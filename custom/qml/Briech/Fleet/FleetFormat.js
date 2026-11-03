.pragma library

// Shared Fleet helpers: one place that turns live QGC vehicle values into the
// text and colours the Fleet panel, Fleet map tags and Fleet page show, so the
// three never disagree. Every helper returns "--" (or NaN) for unknown values;
// none of them invent data.
//
// ".pragma library" makes QML load this file once and share it between every
// file that imports it. It cannot see QML ids, so callers pass in what it needs
// (a vehicle, the vehicle list, the BriechTheme singleton).

/// Battery percentage below which a vehicle counts as low (BATT LOW pill).
var lowBatteryPercent = 20

/// Lowest remaining percentage across the vehicle's packs, or NaN if unknown.
function batteryPercent(vehicle) {
    if (!vehicle || !vehicle.batteries || vehicle.batteries.count === 0) {
        return NaN
    }
    let lowest = NaN
    for (let i = 0; i < vehicle.batteries.count; i++) {
        const battery = vehicle.batteries.get(i)
        const percent = battery && battery.percentRemaining ? Number(battery.percentRemaining.rawValue) : NaN
        if (!isNaN(percent) && (isNaN(lowest) || percent < lowest)) {
            lowest = percent
        }
    }
    return lowest
}

function batteryText(percent) {
    return isNaN(percent) ? "--" : Math.round(percent) + "%"
}

function batteryTone(percent, theme) {
    if (isNaN(percent)) {
        return theme.mutedColor
    }
    return percent > 30 ? theme.okColor : (percent > lowBatteryPercent ? theme.warnColor : theme.errColor)
}

/// MAVLink packets received, as a percentage (100 - loss), or NaN if unknown.
function linkPercent(vehicle) {
    const loss = vehicle ? Number(vehicle.mavlinkLossPercent) : NaN
    return isNaN(loss) ? NaN : Math.round(Math.max(0, Math.min(100, 100 - loss)))
}

function linkTone(percent, theme) {
    if (isNaN(percent)) {
        return theme.mutedColor
    }
    return percent >= 90 ? theme.okColor : (percent >= 70 ? theme.warnColor : theme.errColor)
}

function factText(fact, decimals, suffix) {
    const value = fact ? Number(fact.rawValue) : NaN
    return isNaN(value) ? "--" : value.toFixed(decimals) + suffix
}

/// Heading as three digits and a degree sign, e.g. "007°".
function headingText(vehicle) {
    const heading = vehicle && vehicle.heading ? Number(vehicle.heading.rawValue) : NaN
    return isNaN(heading) ? "--" : ("000" + ((Math.round(heading) % 360 + 360) % 360)).slice(-3) + "°"
}

/// GPS fix type and satellite count, e.g. "3D · 10 SAT".
function gpsText(vehicle) {
    const gps = vehicle ? vehicle.gps : null
    if (!gps) {
        return "--"
    }
    const lock = gps.lock ? Number(gps.lock.rawValue) : NaN
    const count = gps.count ? Number(gps.count.rawValue) : NaN
    // MAVLink GPS_FIX_TYPE values.
    const names = ["NONE", "NO FIX", "2D", "3D", "DGPS", "RTK FLT", "RTK FIX", "STATIC", "PPP"]
    const fix = isNaN(lock) ? "--" : (names[lock] || "--")
    return fix + " · " + (isNaN(count) ? "--" : count) + " SAT"
}

/// Firmware name and version, e.g. "PX4 1.15.4"; "--" until the vehicle reports it.
function firmwareText(vehicle) {
    if (!vehicle) {
        return "--"
    }
    const name = vehicle.firmwareTypeString || ""
    const major = Number(vehicle.firmwareMajorVersion)
    const version = major >= 0
        ? major + "." + vehicle.firmwareMinorVersion + "." + vehicle.firmwarePatchVersion
        : ""
    const text = (name + " " + version).trim()
    return text.length > 0 ? text : "--"
}

// Fleet-wide counts. Called from QML bindings: QML records every vehicle
// property read here, so the counts update whenever one of them changes.

function armedCount(vehicles) {
    let armed = 0
    for (let i = 0; i < vehicles.count; i++) {
        const vehicle = vehicles.get(i)
        if (vehicle && vehicle.armed) {
            armed++
        }
    }
    return armed
}

function flyingCount(vehicles) {
    let flying = 0
    for (let i = 0; i < vehicles.count; i++) {
        const vehicle = vehicles.get(i)
        if (vehicle && vehicle.flying) {
            flying++
        }
    }
    return flying
}

function lowBatteryCount(vehicles) {
    let low = 0
    for (let i = 0; i < vehicles.count; i++) {
        const percent = batteryPercent(vehicles.get(i))
        if (!isNaN(percent) && percent < lowBatteryPercent) {
            low++
        }
    }
    return low
}

/// Lowest link percentage across the fleet, or NaN if no vehicle reports one.
function worstLinkPercent(vehicles) {
    let worst = NaN
    for (let i = 0; i < vehicles.count; i++) {
        const percent = linkPercent(vehicles.get(i))
        if (!isNaN(percent) && (isNaN(worst) || percent < worst)) {
            worst = percent
        }
    }
    return worst
}
