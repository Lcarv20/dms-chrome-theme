package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type Policy struct {
	BrowserThemeColor string `json:"BrowserThemeColor"`
}

type Response struct {
	Status    string   `json:"status"`
	Color     string   `json:"color,omitempty"`
	Browsers  []string `json:"browsers,omitempty"`
	ElapsedMs int64    `json:"elapsed_ms"`
	Error     string   `json:"error,omitempty"`
}

var (
	hexColorRegex = regexp.MustCompile(`^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$`)

	// Standard managed policy directories mapped to their binary refresh commands
	browserTargets = []struct {
		Dir     string
		Binary  string
		ProcKey []string
	}{
		{
			Dir:     "/etc/opt/chrome/policies/managed",
			Binary:  "google-chrome",
			ProcKey: []string{"chrome", "google-chrome"},
		},
		{
			Dir:     "/etc/chromium/policies/managed",
			Binary:  "chromium",
			ProcKey: []string{"chromium", "chromium-browser"},
		},
		{
			Dir:     "/etc/brave/policies/managed",
			Binary:  "brave-browser",
			ProcKey: []string{"brave", "brave-browser"},
		},
	}
)

func normalizeHex(hex string) (string, error) {
	hex = strings.TrimSpace(hex)
	if !hexColorRegex.MatchString(hex) {
		return "", fmt.Errorf("invalid hex color format: %q", hex)
	}
	if !strings.HasPrefix(hex, "#") {
		hex = "#" + hex
	}
	hex = strings.ToLower(hex)
	if len(hex) == 4 {
		// Expand 3-digit hex #rgb -> #rrggbb
		hex = fmt.Sprintf("#%c%c%c%c%c%c", hex[1], hex[1], hex[2], hex[2], hex[3], hex[3])
	}
	return hex, nil
}

func getRunningBrowserProcesses() map[string]bool {
	running := make(map[string]bool)
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return running
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		// Only check numeric process directories
		pid := entry.Name()
		if len(pid) == 0 || pid[0] < '0' || pid[0] > '9' {
			continue
		}

		commPath := filepath.Join("/proc", pid, "comm")
		commBytes, err := os.ReadFile(commPath)
		if err != nil {
			continue
		}
		comm := strings.TrimSpace(string(commBytes))

		for _, target := range browserTargets {
			for _, key := range target.ProcKey {
				if comm == key {
					running[target.Binary] = true
					break
				}
			}
		}
	}
	return running
}

func main() {
	start := time.Now()

	var (
		colorFlag      string
		policyFileFlag string
		forceFlag      bool
		statusFlag     bool
	)

	flag.StringVar(&colorFlag, "color", "", "Target hex color (e.g. '#191920')")
	flag.StringVar(&policyFileFlag, "policy-file", "", "Custom path to color.json policy file")
	flag.BoolVar(&forceFlag, "force", false, "Force apply even if color matches current policy")
	flag.BoolVar(&statusFlag, "status", false, "Show current policy color status")
	flag.Parse()

	respond := func(resp Response) {
		resp.ElapsedMs = time.Since(start).Milliseconds()
		b, _ := json.Marshal(resp)
		fmt.Println(string(b))
		if resp.Status == "error" {
			os.Exit(1)
		}
		os.Exit(0)
	}

	// Status query mode
	if statusFlag {
		targetFile := "/etc/opt/chrome/policies/managed/color.json"
		if policyFileFlag != "" {
			targetFile = policyFileFlag
		}
		data, err := os.ReadFile(targetFile)
		if err != nil {
			respond(Response{Status: "empty", Error: err.Error()})
		}
		var p Policy
		if err := json.Unmarshal(data, &p); err != nil {
			respond(Response{Status: "error", Error: err.Error()})
		}
		respond(Response{Status: "ok", Color: p.BrowserThemeColor})
	}

	if colorFlag == "" {
		respond(Response{Status: "error", Error: "--color flag is required"})
	}

	normColor, err := normalizeHex(colorFlag)
	if err != nil {
		respond(Response{Status: "error", Error: err.Error()})
	}

	// Determine policy target files
	var filesToWrite []string
	if policyFileFlag != "" {
		filesToWrite = append(filesToWrite, policyFileFlag)
	} else {
		for _, target := range browserTargets {
			if _, err := os.Stat(target.Dir); err == nil {
				filesToWrite = append(filesToWrite, filepath.Join(target.Dir, "color.json"))
			}
		}
	}

	if len(filesToWrite) == 0 {
		respond(Response{
			Status: "error",
			Error:  "No managed browser policy directories found (/etc/opt/chrome/policies/managed, etc.)",
		})
	}

	// Fast path check: if all targets already match target color, exit early (noop)
	allMatch := true
	for _, f := range filesToWrite {
		data, err := os.ReadFile(f)
		if err != nil {
			allMatch = false
			break
		}
		var cur Policy
		if err := json.Unmarshal(data, &cur); err != nil || cur.BrowserThemeColor != normColor {
			allMatch = false
			break
		}
	}

	if allMatch && !forceFlag {
		respond(Response{
			Status: "noop",
			Color:  normColor,
		})
	}

	// Write policy files
	policyData, err := json.MarshalIndent(Policy{BrowserThemeColor: normColor}, "", "  ")
	if err != nil {
		respond(Response{Status: "error", Error: err.Error()})
	}
	policyData = append(policyData, '\n')

	for _, f := range filesToWrite {
		dir := filepath.Dir(f)
		_ = os.MkdirAll(dir, 0755)

		// Atomic write via temp file
		tmpFile := fmt.Sprintf("%s.tmp.%d", f, os.Getpid())
		if err := os.WriteFile(tmpFile, policyData, 0644); err != nil {
			respond(Response{Status: "error", Error: fmt.Sprintf("Failed writing %s: %v", tmpFile, err)})
		}
		if err := os.Rename(tmpFile, f); err != nil {
			_ = os.Remove(tmpFile)
			respond(Response{Status: "error", Error: fmt.Sprintf("Failed replacing %s: %v", f, err)})
		}
	}

	// Detect running browsers and trigger synchronous policy refresh
	runningMap := getRunningBrowserProcesses()
	var refreshedBrowsers []string

	for _, target := range browserTargets {
		if !runningMap[target.Binary] {
			continue
		}

		binPath, err := exec.LookPath(target.Binary)
		if err != nil {
			continue
		}

		// Run with 2-second timeout to guarantee it never hangs
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		cmd := exec.CommandContext(ctx, binPath, "--refresh-platform-policy")
		_ = cmd.Run()
		cancel()

		refreshedBrowsers = append(refreshedBrowsers, target.Binary)
	}

	respond(Response{
		Status:   "applied",
		Color:    normColor,
		Browsers: refreshedBrowsers,
	})
}
