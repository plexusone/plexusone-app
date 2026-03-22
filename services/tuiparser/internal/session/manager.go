package session

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/creack/pty"
	"github.com/plexusone/nexus/tuiparser/pkg/protocol"
)

// Session represents an active tmux session connection
type Session struct {
	ID           string
	Name         string
	Status       string
	LastActivity time.Time

	pty    *os.File
	cmd    *exec.Cmd
	mu     sync.Mutex
	output chan []byte
	done   chan struct{}
}

// Manager handles multiple tmux session connections
type Manager struct {
	sessions map[string]*Session
	mu       sync.RWMutex

	// Callbacks
	OnOutput func(sessionID string, data []byte)
	OnStatus func(sessionID string, status string)
}

// NewManager creates a new session manager
func NewManager() *Manager {
	return &Manager{
		sessions: make(map[string]*Session),
	}
}

// ListTmuxSessions returns available tmux sessions
func (m *Manager) ListTmuxSessions() ([]protocol.SessionInfo, error) {
	tmuxPath := findTmux()
	cmd := exec.Command(tmuxPath, "list-sessions", "-F", "#{session_name}:#{session_activity}")
	output, err := cmd.Output()
	if err != nil {
		// No sessions or tmux not running
		return []protocol.SessionInfo{}, nil
	}

	var sessions []protocol.SessionInfo
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ":", 2)
		if len(parts) < 1 {
			continue
		}

		name := parts[0]
		var lastActivity int64
		if len(parts) > 1 {
			fmt.Sscanf(parts[1], "%d", &lastActivity)
		}

		// Determine status based on our tracking
		status := "idle"
		m.mu.RLock()
		if s, ok := m.sessions[name]; ok {
			status = s.Status
		}
		m.mu.RUnlock()

		sessions = append(sessions, protocol.SessionInfo{
			ID:           name,
			Name:         name,
			Status:       status,
			LastActivity: lastActivity,
		})
	}

	return sessions, nil
}

// Attach connects to a tmux session and starts streaming output
func (m *Manager) Attach(sessionName string) (*Session, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if already attached
	if s, ok := m.sessions[sessionName]; ok {
		return s, nil
	}

	// Create PTY and attach to tmux session
	tmuxPath := findTmux()
	cmd := exec.Command(tmuxPath, "attach-session", "-t", sessionName)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := pty.Start(cmd)
	if err != nil {
		return nil, fmt.Errorf("failed to start pty: %w", err)
	}

	session := &Session{
		ID:           sessionName,
		Name:         sessionName,
		Status:       "running",
		LastActivity: time.Now(),
		pty:          ptmx,
		cmd:          cmd,
		output:       make(chan []byte, 100),
		done:         make(chan struct{}),
	}

	m.sessions[sessionName] = session

	// Start reading output
	go m.readOutput(session)

	// Wait for process to exit
	go func() {
		cmd.Wait()
		m.mu.Lock()
		delete(m.sessions, sessionName)
		m.mu.Unlock()
		close(session.done)

		if m.OnStatus != nil {
			m.OnStatus(sessionName, "detached")
		}
	}()

	return session, nil
}

// Detach disconnects from a tmux session
func (m *Manager) Detach(sessionName string) error {
	m.mu.Lock()
	session, ok := m.sessions[sessionName]
	if !ok {
		m.mu.Unlock()
		return fmt.Errorf("session not found: %s", sessionName)
	}
	delete(m.sessions, sessionName)
	m.mu.Unlock()

	// Send detach key sequence (Ctrl-B d)
	session.pty.Write([]byte{0x02, 'd'}) // Ctrl-B, d

	// Close PTY
	session.pty.Close()

	return nil
}

// SendInput sends text input to a session
func (m *Manager) SendInput(sessionName, text string) error {
	m.mu.RLock()
	session, ok := m.sessions[sessionName]
	m.mu.RUnlock()

	if !ok {
		return fmt.Errorf("session not found: %s", sessionName)
	}

	session.mu.Lock()
	defer session.mu.Unlock()

	_, err := session.pty.Write([]byte(text))
	return err
}

// SendKey sends a special key to a session
func (m *Manager) SendKey(sessionName, key string) error {
	m.mu.RLock()
	session, ok := m.sessions[sessionName]
	m.mu.RUnlock()

	if !ok {
		return fmt.Errorf("session not found: %s", sessionName)
	}

	session.mu.Lock()
	defer session.mu.Unlock()

	var data []byte
	switch key {
	case "enter":
		data = []byte{'\r'}
	case "tab":
		data = []byte{'\t'}
	case "escape":
		data = []byte{0x1b}
	case "up":
		data = []byte{0x1b, '[', 'A'}
	case "down":
		data = []byte{0x1b, '[', 'B'}
	case "right":
		data = []byte{0x1b, '[', 'C'}
	case "left":
		data = []byte{0x1b, '[', 'D'}
	case "space":
		data = []byte{' '}
	case "backspace":
		data = []byte{0x7f}
	case "y":
		data = []byte{'y'}
	case "n":
		data = []byte{'n'}
	case "a":
		data = []byte{'a'}
	default:
		return fmt.Errorf("unknown key: %s", key)
	}

	_, err := session.pty.Write(data)
	return err
}

// GetSession returns a session by name
func (m *Manager) GetSession(sessionName string) (*Session, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	s, ok := m.sessions[sessionName]
	return s, ok
}

// readOutput reads from the PTY and sends to callback
func (m *Manager) readOutput(session *Session) {
	buf := make([]byte, 4096)
	for {
		n, err := session.pty.Read(buf)
		if err != nil {
			if err != io.EOF {
				// Log error but don't spam
			}
			return
		}

		if n > 0 {
			session.mu.Lock()
			session.LastActivity = time.Now()
			session.mu.Unlock()

			// Copy data before sending
			data := make([]byte, n)
			copy(data, buf[:n])

			if m.OnOutput != nil {
				m.OnOutput(session.ID, data)
			}
		}
	}
}

// Close shuts down all sessions
func (m *Manager) Close() {
	m.mu.Lock()
	defer m.mu.Unlock()

	for name, session := range m.sessions {
		session.pty.Close()
		delete(m.sessions, name)
	}
}

// findTmux locates the tmux binary
func findTmux() string {
	paths := []string{
		"/opt/homebrew/bin/tmux",
		"/usr/local/bin/tmux",
		"/usr/bin/tmux",
	}

	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	return "tmux"
}
