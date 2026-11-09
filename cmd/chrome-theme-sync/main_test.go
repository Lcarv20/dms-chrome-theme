package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestNormalizeHex(t *testing.T) {
	tests := []struct {
		input    string
		expected string
		wantErr  bool
	}{
		{"#191920", "#191920", false},
		{"191920", "#191920", false},
		{"#FFF", "#ffffff", false},
		{"fff", "#ffffff", false},
		{"#AbC", "#aabbcc", false},
		{"invalid", "", true},
		{"#12345", "", true},
		{"#1234567", "", true},
	}

	for _, tt := range tests {
		got, err := normalizeHex(tt.input)
		if (err != nil) != tt.wantErr {
			t.Errorf("normalizeHex(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			continue
		}
		if got != tt.expected {
			t.Errorf("normalizeHex(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestWriteAndReadPolicy(t *testing.T) {
	tempDir := t.TempDir()
	policyFile := filepath.Join(tempDir, "color.json")

	color := "#393a54"
	norm, err := normalizeHex(color)
	if err != nil {
		t.Fatalf("normalizeHex failed: %v", err)
	}

	policy := Policy{BrowserThemeColor: norm}
	data, err := os.ReadFile(policyFile)
	if err == nil {
		t.Fatalf("expected file to not exist yet")
	}

	data = []byte(`{"BrowserThemeColor": "` + norm + `"}`)
	if err := os.WriteFile(policyFile, data, 0644); err != nil {
		t.Fatalf("failed to write policy: %v", err)
	}

	var read Policy
	content, err := os.ReadFile(policyFile)
	if err != nil {
		t.Fatalf("failed to read policy: %v", err)
	}
	if err := json.Unmarshal(content, &read); err != nil {
		t.Fatalf("failed to unmarshal policy: %v", err)
	}

	if read.BrowserThemeColor != policy.BrowserThemeColor {
		t.Errorf("got %q, want %q", read.BrowserThemeColor, policy.BrowserThemeColor)
	}
}
