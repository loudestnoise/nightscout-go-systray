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

// The `cgm` binary always emits both units; showMgdl only picks which one
// is primary in the UI.
function primaryValue(data, showMgdl) {
    return showMgdl ? String(data.mgdl) : data.mmol.toFixed(1);
}

function primaryUnit(showMgdl) {
    return showMgdl ? "mg/dL" : "mmol/L";
}

function secondaryValueText(data, showMgdl) {
    return showMgdl ? (data.mmol.toFixed(1) + " mmol/L") : (data.mgdl + " mg/dL");
}

function pillText(data, showMgdl) {
    if (!data) return "…";
    if (!hasReading(data)) return "⚠ CGM";
    var arrow = data.directionArrow || "";
    return statusGlyph(data) + " " + primaryValue(data, showMgdl) + " " + arrow;
}

function pillTooltip(data, showMgdl) {
    if (!data) return "Nightscout CGM — loading…";
    if (!hasReading(data)) return "Nightscout CGM — " + (data.error || "no data");
    return primaryValue(data, showMgdl) + " " + primaryUnit(showMgdl) + " (" +
        secondaryValueText(data, showMgdl) + ") " +
        (data.directionArrow || "") + " · " + minutesAgoText(data.timestampMs);
}

// "Previous: 5.3 mmol/L" / "Previous: 95 mg/dL" for the popup. Caller must
// have already checked hasPrevious (typeof data.previousMmol === "number").
function previousValueText(data, showMgdl) {
    return showMgdl ? (data.previousMgdl + " mg/dL") : (data.previousMmol.toFixed(1) + " mmol/L");
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
