package server

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
)

// TokenEnvVar is the environment variable read for the token when the
// --token flag is empty.
const TokenEnvVar = "TUIPARSER_TOKEN"

// IsLoopbackHost reports whether host names only the local machine:
// "localhost" or a loopback IP such as 127.0.0.1 or ::1. An empty host or an
// unspecified address such as 0.0.0.0 listens on every interface and is not
// loopback; any other hostname is treated as non-loopback.
func IsLoopbackHost(host string) bool {
	host = strings.TrimSuffix(strings.TrimPrefix(host, "["), "]")
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// ValidateListenConfig checks that the server is not exposed beyond the local
// machine without a token. It returns an error explaining how to set one.
func ValidateListenConfig(host, token string) error {
	if token != "" || IsLoopbackHost(host) {
		return nil
	}
	return fmt.Errorf("refusing to listen on non-loopback host %q without a token: "+
		"anyone who can reach this port could type commands into your tmux sessions; "+
		"set %s (preferred) or pass --token, for example %s=$(openssl rand -hex 32), "+
		"or keep the default --host 127.0.0.1 and connect through an SSH tunnel", host, TokenEnvVar, TokenEnvVar)
}

// GenerateToken returns a random 256-bit token, hex encoded.
func GenerateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// requestToken returns the token a request presents, from an
// "Authorization: Bearer <token>" header or, for WebSocket clients that
// cannot set headers, a "token" query parameter.
func requestToken(r *http.Request) string {
	if auth := r.Header.Get("Authorization"); auth != "" {
		scheme, value, ok := strings.Cut(auth, " ")
		if ok && strings.EqualFold(scheme, "Bearer") {
			return strings.TrimSpace(value)
		}
	}
	return r.URL.Query().Get("token")
}

// TokenAuthorized reports whether r carries the expected token. An empty
// expected token disables the check. Tokens are hashed before a constant-time
// comparison so neither content nor length leaks through timing.
func TokenAuthorized(r *http.Request, expected string) bool {
	if expected == "" {
		return true
	}
	got := requestToken(r)
	if got == "" {
		return false
	}
	gotSum := sha256.Sum256([]byte(got))
	wantSum := sha256.Sum256([]byte(expected))
	return subtle.ConstantTimeCompare(gotSum[:], wantSum[:]) == 1
}

// RequireToken wraps next so requests without the expected token get
// 401 Unauthorized. With no token (loopback only), it instead requires the
// Host header to name this machine, which stops DNS rebinding: a web page
// whose domain was re-pointed at 127.0.0.1 sends its own domain as Host,
// and would otherwise also pass the Origin check.
func RequireToken(token string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if token == "" && !RequestHostIsLoopback(r) {
			http.Error(w, "forbidden host", http.StatusForbidden)
			return
		}
		if !TokenAuthorized(r, token) {
			w.Header().Set("WWW-Authenticate", `Bearer realm="tuiparser"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// RequestHostIsLoopback reports whether the request's Host header names
// this machine (localhost or a loopback IP, with any port).
func RequestHostIsLoopback(r *http.Request) bool {
	host := r.Host
	if h, _, err := net.SplitHostPort(r.Host); err == nil {
		host = h
	}
	return IsLoopbackHost(host)
}

// CheckOrigin allows requests without an Origin header (native mobile
// clients do not send one) and browser requests whose Origin host matches
// the request Host. Any other origin, including "null", is rejected, which
// stops other web pages from opening a WebSocket to this server.
func CheckOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return false
	}
	return strings.EqualFold(u.Host, r.Host)
}
