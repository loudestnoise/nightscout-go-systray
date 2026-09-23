// Command cgm is a stateless Nightscout CGM data backend for the Omarchy
// shell plugin (see omarchy-plugin/). It fetches the latest two entries from
// a Nightscout instance, computes range/trend/prediction state, and prints a
// single JSON object to stdout, then exits. It is designed to be invoked
// repeatedly by the plugin's own poll timer rather than run as a long-lived
// process, so it carries no persisted state between runs.
//
// This is a trimmed-down descendant of the original nightscout-go-systray
// tray app: the systray UI, desktop notifications, and BoltDB-backed
// settings have all moved into the Omarchy plugin (QML) side. See the
// project README for attribution to the original authors.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const mgdlToMmol = 18.018018018
const predictLowSeconds = 3600

type direction struct {
	Arrow      string
	IsRising   bool
	IsFalling  bool
	IsFallback bool
}

var directions = map[string]direction{
	"TripleUp":      {Arrow: "⤊", IsRising: true},
	"DoubleUp":      {Arrow: "⇈", IsRising: true},
	"SingleUp":      {Arrow: "↑", IsRising: true},
	"FortyFiveUp":   {Arrow: "↗"},
	"Flat":          {Arrow: "→"},
	"FortyFiveDown": {Arrow: "↘"},
	"SingleDown":    {Arrow: "↓", IsFalling: true},
	"DoubleDown":    {Arrow: "⇊", IsFalling: true},
	"TripleDown":    {Arrow: "⤋", IsFalling: true},
	"None":          {Arrow: "-", IsFallback: true},
}

const fallbackDirection = "None"

type flags struct {
	Url        *string
	UrgentHigh *float64
	High       *float64
	Low        *float64
}

type entry struct {
	Date      int64  `json:"date"`
	Sgv       int    `json:"sgv"`
	Direction string `json:"direction"`
}

// reading is one CGM data point, already converted to mmol/L.
type reading struct {
	TimestampMs int64
	Mmol        float64
	Direction   string
}

func (r reading) isUrgentHigh(args flags) bool { return r.Mmol >= *args.UrgentHigh }
func (r reading) isHigh(args flags) bool       { return r.Mmol >= *args.High }
func (r reading) isLow(args flags) bool        { return r.Mmol < *args.Low }

// output is the JSON payload printed to stdout for the Omarchy plugin to
// parse. Field names are part of the plugin's contract with this binary.
type output struct {
	FetchedAtMs      int64    `json:"fetchedAtMs"`
	Mmol             float64  `json:"mmol"`
	Mgdl             int      `json:"mgdl"`
	TimestampMs      int64    `json:"timestampMs"`
	Direction        string   `json:"direction"`
	DirectionArrow   string   `json:"directionArrow"`
	PreviousMmol     *float64 `json:"previousMmol,omitempty"`
	PreviousMgdl     *int     `json:"previousMgdl,omitempty"`
	PreviousTsMs     *int64   `json:"previousTimestampMs,omitempty"`
	IsLow            bool     `json:"isLow"`
	IsHigh           bool     `json:"isHigh"`
	IsUrgentHigh     bool     `json:"isUrgentHigh"`
	PredictedLowAtMs *int64   `json:"predictedLowAtMs,omitempty"`
	InRangeAtMs      *int64   `json:"inRangeAtMs,omitempty"`
	Alerts           []string `json:"alerts"`
	Error            string   `json:"error,omitempty"`
}

func main() {
	args := flags{
		Url:        flag.String("url", "", "Your nightscout url e.g. https://example.herokuapp.com"),
		UrgentHigh: flag.Float64("urgent-high", 15.0, "Your BG urgent high target (mmol/L)"),
		High:       flag.Float64("high", 8.0, "Your BG high target (mmol/L)"),
		Low:        flag.Float64("low", 4.0, "Your BG low target (mmol/L)"),
	}
	flag.Parse()

	if *args.Url == "" {
		fail("a nightscout URL is required")
	}

	current, previous, err := fetchEntries(*args.Url)
	if err != nil {
		fail(err.Error())
	}

	emit(buildOutput(args, current, previous))
}

func fail(msg string) {
	emit(output{
		FetchedAtMs: time.Now().UnixMilli(),
		Error:       msg,
		Alerts:      []string{},
	})
	os.Exit(1)
}

func emit(o output) {
	if o.Alerts == nil {
		o.Alerts = []string{}
	}
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(o); err != nil {
		fmt.Fprintln(os.Stderr, "failed to encode output:", err)
		os.Exit(1)
	}
}

// fetchEntries fetches the two most recent Nightscout entries and returns
// them as (current, previous). previous is nil if Nightscout only has one
// entry.
func fetchEntries(nightscoutUrl string) (current reading, previous *reading, err error) {
	url := strings.TrimRight(nightscoutUrl, "/") + "/api/v1/entries.json?count=2"

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return reading{}, nil, fmt.Errorf("fetch error: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return reading{}, nil, fmt.Errorf("read error: %w", err)
	}

	var entries []entry
	if err := json.Unmarshal(body, &entries); err != nil || len(entries) == 0 {
		return reading{}, nil, fmt.Errorf("failed to parse entries: %v", err)
	}

	current = reading{
		TimestampMs: entries[0].Date,
		Mmol:        float64(entries[0].Sgv) / mgdlToMmol,
		Direction:   entries[0].Direction,
	}
	if len(entries) > 1 {
		p := reading{
			TimestampMs: entries[1].Date,
			Mmol:        float64(entries[1].Sgv) / mgdlToMmol,
			Direction:   entries[1].Direction,
		}
		previous = &p
	}

	return current, previous, nil
}

func buildOutput(args flags, current reading, previous *reading) output {
	dir, ok := directions[current.Direction]
	if !ok {
		dir = directions[fallbackDirection]
	}

	mgdl := int(current.Mmol*mgdlToMmol + 0.5)
	o := output{
		FetchedAtMs:    time.Now().UnixMilli(),
		Mmol:           round1(current.Mmol),
		Mgdl:           mgdl,
		TimestampMs:    current.TimestampMs,
		Direction:      current.Direction,
		DirectionArrow: dir.Arrow,
		IsLow:          current.isLow(args),
		IsHigh:         current.isHigh(args),
		IsUrgentHigh:   current.isUrgentHigh(args),
		Alerts:         []string{},
	}

	if previous == nil {
		return o
	}

	prevMmol := round1(previous.Mmol)
	prevMgdl := int(previous.Mmol*mgdlToMmol + 0.5)
	prevTs := previous.TimestampMs
	o.PreviousMmol = &prevMmol
	o.PreviousMgdl = &prevMgdl
	o.PreviousTsMs = &prevTs

	o.PredictedLowAtMs = predictedLowAtMs(args, current, *previous)
	o.InRangeAtMs = predictedInRangeAtMs(args, current, *previous)
	o.Alerts = alerts(args, current, dir, *previous, o.PredictedLowAtMs)

	return o
}

func alerts(args flags, current reading, dir direction, previous reading, predictedLowAtMs *int64) []string {
	var out []string

	if dir.IsFallback {
		out = append(out, fmt.Sprintf("Failed to get BG direction. %.1f", current.Mmol))
	} else if current.Mmol != previous.Mmol {
		if dir.IsRising {
			out = append(out, fmt.Sprintf("Rising fast! %.1f %s", current.Mmol, dir.Arrow))
		} else if dir.IsFalling {
			out = append(out, fmt.Sprintf("Falling fast! %.1f %s", current.Mmol, dir.Arrow))
		}
	}

	if current.isLow(args) {
		out = append(out, fmt.Sprintf("Low! %.1f %s", current.Mmol, dir.Arrow))
	} else if current.isUrgentHigh(args) {
		out = append(out, fmt.Sprintf("Urgent high! %.1f %s", current.Mmol, dir.Arrow))
	}

	if predictedLowAtMs != nil {
		t := time.UnixMilli(*predictedLowAtMs)
		out = append(out, fmt.Sprintf("Predicted low at %s!", t.Format("15:04")))
	}

	return out
}

// predictedLowAtMs extrapolates a straight line from previous->current and
// returns when it would cross the low threshold, if current is falling and
// that crossing is still ahead (not already-low, and not so far out it's
// not a meaningful warning).
func predictedLowAtMs(args flags, current reading, previous reading) *int64 {
	if current.TimestampMs == previous.TimestampMs || current.Mmol >= previous.Mmol {
		return nil
	}
	seconds := float64(current.TimestampMs-previous.TimestampMs) / 1000
	if seconds <= 0 {
		return nil
	}
	changePerSecond := (previous.Mmol - current.Mmol) / seconds
	if changePerSecond <= 0 {
		return nil
	}
	secondsToLow := (current.Mmol - *args.Low) / changePerSecond
	predicted := time.Now().Add(time.Duration(secondsToLow) * time.Second)
	if !predicted.After(time.Now()) || !predicted.Before(time.Now().Add(predictLowSeconds*time.Second)) {
		return nil
	}
	at := predicted.UnixMilli()
	return &at
}

// predictedInRangeAtMs extrapolates when a current high/low reading would
// cross back into range, given the direction of change since previous.
func predictedInRangeAtMs(args flags, current reading, previous reading) *int64 {
	if current.TimestampMs == previous.TimestampMs {
		return nil
	}
	seconds := absFloat(float64(current.TimestampMs-previous.TimestampMs) / 1000)
	if seconds <= 0 {
		return nil
	}
	changePerSecond := absFloat((previous.Mmol - current.Mmol) / seconds)
	if changePerSecond <= 0 {
		return nil
	}

	var secondsToInRange float64
	switch {
	case current.isHigh(args) && current.Mmol < previous.Mmol:
		secondsToInRange = (current.Mmol - *args.High) / changePerSecond
	case current.isLow(args) && current.Mmol > previous.Mmol:
		secondsToInRange = (*args.Low - current.Mmol) / changePerSecond
	default:
		return nil
	}

	at := time.Now().Add(time.Duration(secondsToInRange) * time.Second).UnixMilli()
	return &at
}

func round1(v float64) float64 {
	return float64(int(v*10+0.5)) / 10
}

func absFloat(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}
