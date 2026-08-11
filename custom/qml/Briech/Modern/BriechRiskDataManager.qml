import QtQuick

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property url sourceUrl: ""
    property bool autoRefresh: sourceUrl !== ""
    property int refreshIntervalMs: 60000
    property var zones: []
    property var weatherAlerts: []
    property string status: "idle"
    property string lastError: ""
    property string apiKey: ""
    property string apiKeyHeader: "x-openaip-api-key"
    property int minRequestIntervalMs: 20000
    property int rateLimitCooldownMs: 120000
    property double lastRequestMs: 0
    property double cooldownUntilMs: 0
    readonly property bool hasData: zones.length > 0 || weatherAlerts.length > 0

    signal refreshed()
    signal failed(string message)
    signal deferred(int delayMs)

    function isLocalUrl(url) {
        const value = String(url || "")
        return value.indexOf("qrc:") === 0 || value.indexOf("file:") === 0
    }

    function coordinateFromLonLat(position) {
        if (!position || position.length < 2) {
            return null
        }
        return { lat: Number(position[1]), lon: Number(position[0]), alt: Number(position[2] || 0) }
    }

    function coordinateFromAny(value) {
        if (!value) {
            return null
        }
        if (value.latitude !== undefined && value.longitude !== undefined) {
            return { lat: Number(value.latitude), lon: Number(value.longitude), alt: Number(value.altitude || 0) }
        }
        if (value.lat !== undefined && value.lon !== undefined) {
            return { lat: Number(value.lat), lon: Number(value.lon), alt: Number(value.alt || 0) }
        }
        if (value.length >= 2) {
            return coordinateFromLonLat(value)
        }
        return null
    }

    function pathFromRing(ring) {
        const path = []
        for (let i = 0; ring && i < ring.length; i++) {
            const coordinate = coordinateFromAny(ring[i])
            if (coordinate && !isNaN(coordinate.lat) && !isNaN(coordinate.lon)) {
                path.push(coordinate)
            }
        }
        return path
    }

    function pathFromGeometry(geometry) {
        if (!geometry || !geometry.coordinates) {
            return []
        }
        let ring = []
        if (geometry.type === "Polygon" && geometry.coordinates.length > 0) {
            ring = geometry.coordinates[0]
        } else if (geometry.type === "MultiPolygon" && geometry.coordinates.length > 0 && geometry.coordinates[0].length > 0) {
            ring = geometry.coordinates[0][0]
        } else if (geometry.type === "LineString") {
            ring = geometry.coordinates
        } else if (geometry.coordinates.length > 0) {
            ring = geometry.coordinates
        }

        return pathFromRing(ring)
    }

    function pathFromValue(value) {
        if (!value) {
            return []
        }
        if (value.coordinates !== undefined) {
            return pathFromGeometry(value)
        }
        if (value.length > 0 && value[0] && value[0].length > 0 && value[0][0] && value[0][0].length >= 2) {
            return pathFromRing(value[0])
        }
        return pathFromRing(value)
    }

    function classifiedZoneKind(value) {
        const key = String(value || "").toLowerCase()
        if (key.indexOf("nfz") !== -1 || key.indexOf("no-fly") !== -1 || key.indexOf("nofly") !== -1 || key.indexOf("prohibited") !== -1 || key.indexOf("danger") !== -1) {
            return "nfz"
        }
        if (key.indexOf("restricted") !== -1 || key === "r" || key.indexOf("temporary") !== -1 || key.indexOf("military") !== -1) {
            return "restricted"
        }
        if (key.indexOf("radar") !== -1 || key.indexOf("radio") !== -1 || key.indexOf("transponder") !== -1) {
            return "radar"
        }
        if (key.indexOf("advisory") !== -1 || key.indexOf("airspace") !== -1 || key.indexOf("control") !== -1 || key.indexOf("ctr") !== -1 || key.indexOf("tmz") !== -1 || key.indexOf("rmz") !== -1) {
            return "advisory"
        }
        return key || "advisory"
    }

    function normalizeFeature(feature, index) {
        const properties = feature.properties || {}
        const rawKind = properties.kind || properties.type || properties.category || properties.airspaceType || properties.class || properties.icaoClass || "airspace"
        return normalizeZone({
            id: feature.id || properties.id || properties._id,
            kind: classifiedZoneKind(rawKind),
            label: properties.label || properties.name || properties.title || properties.designator || "",
            active: properties.active !== false && properties.enabled !== false,
            path: pathFromGeometry(feature.geometry),
            center: properties.center || null,
            severity: properties.severity || properties.level || "advisory",
            color: properties.color || "",
            fillColor: properties.fillColor || "",
            source: properties.source || "geojson"
        }, index)
    }

    function firstValidPath(zone) {
        if (zone.path && zone.path.length >= 3) {
            return zone.path
        }
        const coordinatesPath = pathFromValue(zone.coordinates)
        if (coordinatesPath.length >= 3) {
            return coordinatesPath
        }
        const polygonPath = pathFromValue(zone.polygon)
        if (polygonPath.length >= 3) {
            return polygonPath
        }
        return pathFromGeometry(zone.geometry)
    }

    function normalizeZone(zone, index) {
        if (!zone) {
            return null
        }
        const rawKind = zone.kind || zone.type || zone.category || zone.airspaceType || zone.class || zone.icaoClass || "airspace"
        return {
            id: zone.id || zone.uuid || ("zone-" + index),
            kind: classifiedZoneKind(rawKind),
            label: zone.label || zone.name || zone.title || zone.designator || "",
            active: zone.active !== false && zone.enabled !== false,
            path: firstValidPath(zone),
            center: zone.center || null,
            severity: zone.severity || zone.level || "advisory",
            color: zone.color || zone.borderColor || "",
            fillColor: zone.fillColor || "",
            source: zone.source || "risk-data"
        }
    }

    function normalizeAlert(alert, index) {
        if (!alert) {
            return null
        }
        return {
            id: alert.id || alert.uuid || ("alert-" + index),
            type: alert.type || alert.category || "",
            label: alert.label || alert.title || "",
            message: alert.message || alert.description || "",
            active: alert.active !== false && alert.enabled !== false,
            severity: alert.severity || alert.level || "info",
            source: alert.source || "risk-data"
        }
    }

    function firstArrayPayload(payload) {
        if (!payload) {
            return []
        }
        if (payload instanceof Array) {
            return payload
        }
        if (payload.type === "FeatureCollection" && payload.features) {
            return payload.features
        }

        const keys = ["riskZones", "zones", "airspace", "airspaces", "items", "data", "results", "features"]
        for (let i = 0; i < keys.length; i++) {
            const value = payload[keys[i]]
            if (value instanceof Array) {
                return value
            }
            const nested = firstArrayPayload(value)
            if (nested.length > 0) {
                return nested
            }
        }
        return []
    }

    function applyPayload(payload) {
        const zoneSource = firstArrayPayload(payload)
        const alertSource = payload.weatherAlerts || payload.alerts || payload.weather || []
        const nextZones = []
        const nextAlerts = []

        for (let i = 0; i < zoneSource.length; i++) {
            const zone = zoneSource[i] && zoneSource[i].type === "Feature" ? normalizeFeature(zoneSource[i], i) : normalizeZone(zoneSource[i], i)
            if (zone && zone.active && zone.path.length >= 3) {
                nextZones.push(zone)
            }
        }

        for (let j = 0; j < alertSource.length; j++) {
            const alert = normalizeAlert(alertSource[j], j)
            if (alert && alert.active) {
                nextAlerts.push(alert)
            }
        }

        zones = nextZones
        weatherAlerts = nextAlerts
        status = "ready"
        lastError = ""
        refreshed()
    }

    function refresh() {
        if (sourceUrl === "") {
            status = "idle"
            zones = []
            weatherAlerts = []
            return
        }

        const now = Date.now()
        if (cooldownUntilMs > now) {
            const cooldownDelay = Math.max(1000, Math.round(cooldownUntilMs - now))
            status = "error"
            lastError = "Risk data rate limited. Cooling down for " + Math.ceil(cooldownDelay / 1000) + "s"
            deferred(cooldownDelay)
            return
        }

        const elapsed = now - lastRequestMs
        if (lastRequestMs > 0 && elapsed < minRequestIntervalMs) {
            deferred(Math.max(1000, Math.round(minRequestIntervalMs - elapsed)))
            return
        }

        lastRequestMs = now
        status = "loading"
        zones = []
        weatherAlerts = []
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) {
                return
            }

            if (request.status === 0 && !isLocalUrl(sourceUrl)) {
                status = "error"
                lastError = "Risk data request failed: network unavailable, blocked, or TLS rejected"
                failed(lastError)
                return
            }

            if (request.status !== 200 && request.status !== 0) {
                status = "error"
                let responseMessage = ""
                try {
                    const errorPayload = JSON.parse(request.responseText)
                    responseMessage = errorPayload.message || errorPayload.error || ""
                } catch (parseError) {
                    responseMessage = request.responseText ? String(request.responseText).slice(0, 120) : ""
                }
                if (request.status === 429) {
                    cooldownUntilMs = Date.now() + rateLimitCooldownMs
                    lastError = "Risk data request failed: HTTP 429 - provider rate limit. Waiting " + Math.ceil(rateLimitCooldownMs / 1000) + "s before retry."
                    deferred(rateLimitCooldownMs)
                } else {
                    lastError = "Risk data request failed: HTTP " + request.status + (responseMessage ? " - " + responseMessage : "")
                }
                failed(lastError)
                return
            }

            try {
                applyPayload(JSON.parse(request.responseText))
            } catch (error) {
                status = "error"
                lastError = "Risk data parse failed: " + error
                failed(lastError)
            }
        }
        request.open("GET", sourceUrl)
        if (apiKey !== "" && apiKeyHeader !== "") {
            request.setRequestHeader(apiKeyHeader, apiKey)
        }
        request.setRequestHeader("Accept", "application/json")
        request.send()
    }

    function loadFromUrl(url) {
        sourceUrl = url || ""
        refresh()
    }

    function clear() {
        status = "idle"
        lastError = ""
        zones = []
        weatherAlerts = []
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: root.autoRefresh && root.sourceUrl !== ""
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
