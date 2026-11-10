.pragma library

// Shared Fleet helpers: one place that turns live QGC vehicle values and
// coordinator rows into the text and colours the Fleet panel, Fleet map layers
// and Fleet page show, so they never disagree. Every helper returns "--" (or NaN) for unknown values;
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
/// Call it from a timer, not a binding: QGC announces mavlinkLossPercent on
/// every MAVLink message, so a binding reading it re-runs hundreds of times a
/// second. sampleLinkPercents() is the once-a-second version for views.
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

// Coordinator rows (FleetAssetModel, FleetObjectModel, FleetAlertModel). A field
// the coordinator left out arrives as undefined.

function has(value) {
    return value !== undefined && value !== null
}

/// Confidence 0..1 as a whole percent, e.g. "88%".
function confidenceText(confidence) {
    return has(confidence) && !isNaN(Number(confidence)) ? Math.round(Number(confidence) * 100) + "%" : "--"
}

/// Seconds as "4s", "3m" or "2h".
function ageText(seconds) {
    if (!has(seconds) || isNaN(Number(seconds))) {
        return "--"
    }
    const s = Math.max(0, Math.floor(Number(seconds)))
    return s < 60 ? s + "s" : (s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + "h")
}

/// Upper case with spaces for schema words: "person", "north_fence" -> "NORTH FENCE".
function wordText(value) {
    return has(value) && String(value).length > 0 ? String(value).replace(/_/g, " ").toUpperCase() : "--"
}

/// Position error, e.g. "±6 m".
function errorText(pos) {
    return pos && has(pos.error_m) ? "±" + Math.round(Number(pos.error_m)) + " m" : "--"
}

function severityTone(severity, theme) {
    return severity === "high" ? theme.errColor
         : severity === "medium" ? theme.warnColor
         : severity === "low" ? theme.blueColor
         : theme.mutedColor
}

function healthTone(health, theme) {
    return health === "ok" ? theme.okColor
         : health === "degraded" ? theme.warnColor
         : health === "fault" ? theme.errColor
         : theme.mutedColor
}

// Drone data age (FleetDataAge.levels): -1 never heard, 0 fresh, 1 amber
// (older than 3 s), 2 grey (older than 10 s, stale).
var ageUnknown = -1
var ageFresh = 0
var ageAmber = 1
var ageGrey = 2

/// The level FleetDataAge publishes for vehicle id, or ageUnknown.
function vehicleAgeLevel(levels, id) {
    const level = levels ? levels[String(id)] : undefined
    return level === undefined ? ageUnknown : Number(level)
}

/// Whole seconds since vehicle id was heard, or undefined ("--").
function vehicleAgeSeconds(seconds, id) {
    return seconds ? seconds[String(id)] : undefined
}

function ageTone(level, theme) {
    return level === ageAmber ? theme.warnColor
         : level === ageGrey ? theme.mutedColor
         : level === ageFresh ? theme.okColor
         : theme.mutedColor
}

/// online, offline or unknown: the coordinator's view of an asset's link.
function assetLinkTone(link, theme) {
    return link === "online" ? theme.okColor : (link === "offline" ? theme.errColor : theme.mutedColor)
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

/// {vehicle id: link percent} for every vehicle that reports one. Views call
/// this from a 1 s timer and bind to the result.
function sampleLinkPercents(vehicles) {
    const map = {}
    for (let i = 0; i < vehicles.count; i++) {
        const vehicle = vehicles.get(i)
        const percent = linkPercent(vehicle)
        if (vehicle && !isNaN(percent)) {
            map[String(vehicle.id)] = percent
        }
    }
    return map
}

/// A vehicle's sampled link percent, or NaN ("--").
function sampledLink(map, id) {
    const percent = map ? map[String(id)] : undefined
    return percent === undefined ? NaN : percent
}

/// Lowest link percentage in a sampleLinkPercents() map, or NaN if none.
function worstLinkPercent(map) {
    let worst = NaN
    for (const id in map) {
        if (isNaN(worst) || map[id] < worst) {
            worst = map[id]
        }
    }
    return worst
}
