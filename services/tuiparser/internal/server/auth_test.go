package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestIsLoopbackHost(t *testing.T) {
	tests := map[string]bool{
		"127.0.0.1":     true,
		"127.0.0.2":     true,
		"::1":           true,
		"[::1]":         true,
		"localhost":     true,
		"LocalHost":     true,
		"":              false,
		"0.0.0.0":       false,
		"::":            false,
		"192.168.1.10":  false,
		"100.64.0.1":    false,
		"example.local": false,
	}
	for host, want := range tests {
		if got := IsLoopbackHost(host); got != want {
			t.Errorf("IsLoopbackHost(%q) = %v, want %v", host, got, want)
		}
	}
}

func TestValidateListenConfig(t *testing.T) {
	tests := []struct {
		host, token string
		wantErr     bool
	}{
		{"127.0.0.1", "", false},
		{"localhost", "", false},
		{"::1", "", false},
		{"127.0.0.1", "secret", false},
		{"0.0.0.0", "secret", false},
		{"192.168.1.10", "secret", false},
		{"0.0.0.0", "", true},
		{"", "", true},
		{"192.168.1.10", "", true},
	}
	for _, tt := range tests {
		err := ValidateListenConfig(tt.host, tt.token)
		if (err != nil) != tt.wantErr {
			t.Errorf("ValidateListenConfig(%q, %q) error = %v, wantErr %v", tt.host, tt.token, err, tt.wantErr)
		}
		if err != nil && !strings.Contains(err.Error(), TokenEnvVar) {
			t.Errorf("error %q does not explain how to set %s", err, TokenEnvVar)
		}
	}
}

func TestGenerateToken(t *testing.T) {
	a, err := GenerateToken()
	if err != nil {
		t.Fatal(err)
	}
	b, err := GenerateToken()
	if err != nil {
		t.Fatal(err)
	}
	if len(a) != 64 {
		t.Errorf("token length = %d, want 64", len(a))
	}
	if a == b {
		t.Error("two generated tokens are equal")
	}
}

func TestTokenAuthorized(t *testing.T) {
	tests := []struct {
		name     string
		expected string
		target   string
		header   string
		want     bool
	}{
		{"no token configured", "", "/ws", "", true},
		{"missing", "secret", "/ws", "", false},
		{"bearer header", "secret", "/ws", "Bearer secret", true},
		{"bearer lowercase scheme", "secret", "/ws", "bearer secret", true},
		{"wrong bearer", "secret", "/ws", "Bearer nope", false},
		{"prefix of token", "secret", "/ws", "Bearer secre", false},
		{"basic scheme ignored", "secret", "/ws", "Basic secret", false},
		{"query param", "secret", "/ws?token=secret", "", true},
		{"encoded query param", "a b&c", "/ws?token=a%20b%26c", "", true},
		{"wrong query param", "secret", "/ws?token=nope", "", false},
		{"empty query param", "secret", "/ws?token=", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, tt.target, nil)
			if tt.header != "" {
				r.Header.Set("Authorization", tt.header)
			}
			if got := TokenAuthorized(r, tt.expected); got != tt.want {
				t.Errorf("TokenAuthorized = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestRequireToken(t *testing.T) {
	called := false
	h := RequireToken("secret", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	})

	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodGet, "/ws", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("status without token = %d, want 401", rec.Code)
	}
	if called {
		t.Error("handler ran without a token")
	}

	rec = httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodGet, "/ws?token=secret", nil))
	if rec.Code != http.StatusOK || !called {
		t.Errorf("status with token = %d, called = %v; want 200, true", rec.Code, called)
	}
}

func TestRequireTokenWithoutTokenRejectsForeignHost(t *testing.T) {
	h := RequireToken("", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	tests := []struct {
		host string
		want int
	}{
		{"localhost:9600", http.StatusOK},
		{"127.0.0.1:9600", http.StatusOK},
		{"[::1]:9600", http.StatusOK},
		{"localhost", http.StatusOK},
		// A rebound domain sends its own name as Host.
		{"evil.example:9600", http.StatusForbidden},
		{"192.168.1.20:9600", http.StatusForbidden},
	}
	for _, tt := range tests {
		t.Run(tt.host, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/ws", nil)
			r.Host = tt.host
			rec := httptest.NewRecorder()
			h(rec, r)
			if rec.Code != tt.want {
				t.Errorf("host %q: status = %d, want %d", tt.host, rec.Code, tt.want)
			}
		})
	}
}

func TestCheckOrigin(t *testing.T) {
	tests := []struct {
		name   string
		host   string
		origin string
		want   bool
	}{
		{"no origin (native client)", "192.168.1.10:9600", "", true},
		{"same origin", "localhost:9600", "http://localhost:9600", true},
		{"same origin case-insensitive", "LOCALHOST:9600", "http://localhost:9600", true},
		{"other site", "localhost:9600", "https://evil.example", false},
		{"different port", "localhost:9600", "http://localhost:8080", false},
		{"null origin", "localhost:9600", "null", false},
		{"malformed origin", "localhost:9600", "://", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/ws", nil)
			r.Host = tt.host
			if tt.origin != "" {
				r.Header.Set("Origin", tt.origin)
			}
			if got := CheckOrigin(r); got != tt.want {
				t.Errorf("CheckOrigin = %v, want %v", got, tt.want)
			}
		})
	}
}
