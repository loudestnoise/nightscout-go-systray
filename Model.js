.pragma library

// Formatting helpers for the Nightscout CGM plugin's Panel/BarWidget.
// Kept separate from the QML so the JSON-shape <-> display-string mapping
// (the contract with the `cgm` binary's stdout) is easy to find and test.

// True only when `data` is a successfully-parsed reading with a numeric
// mmol value -- as opposed to null (not fetched yet) or an {error: ...}
// object from a failed fetch. Every accessor below must gate on this
// instead of plain truthiness, since {error: "..."} is itself truthy.
function hasReading(data) {
    return !!data && !data.error && typeof data.mmol === "number";
}

function statusGlyph(data) {
    if (!hasReading(data)) return "⚠";
    if (data.isLow || data.isUrgentHigh) return "🔴";
    if (data.isHigh) return "🟠";
    return "🟢";
}

function pillText(data) {
    if (!data) return "…";
    if (!hasReading(data)) return "⚠ CGM";
    var arrow = data.directionArrow || "";
    return statusGlyph(data) + " " + data.mmol.toFixed(1) + " " + arrow;
}

function pillTooltip(data) {
    if (!data) return "Nightscout CGM — loading…";
    if (!hasReading(data)) return "Nightscout CGM — " + (data.error || "no data");
    return data.mmol.toFixed(1) + " mmol/L (" + data.mgdl + " mg/dL) " +
        (data.directionArrow || "") + " · " + minutesAgoText(data.timestampMs);
}

function minutesAgoText(timestampMs) {
    if (!timestampMs) return "unknown";
    var mins = Math.max(0, Math.round((Date.now() - timestampMs) / 60000));
    if (mins === 0) return "just now";
    return mins + (mins === 1 ? " minute ago" : " minutes ago");
}

function formatClock(ms) {
    if (!ms) return "";
    var d = new Date(ms);
    var hh = String(d.getHours()).padStart(2, "0");
    var mm = String(d.getMinutes()).padStart(2, "0");
    return hh + ":" + mm;
}

// Builds the `cgm` binary's argv from the plugin settings object.
function cliArgs(cliPath, settings) {
    return [
        cliPath,
        "-url", String(settings.nightscoutUrl || ""),
        "-low", String(settings.lowMmol),
        "-high", String(settings.highMmol),
        "-urgent-high", String(settings.urgentHighMmol)
    ];
}
