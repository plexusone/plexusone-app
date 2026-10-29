package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/plexusone/nexus/tuiparser/internal/server"
	"github.com/plexusone/nexus/tuiparser/internal/session"
)

func main() {
	port := flag.Int("port", 9600, "WebSocket server port")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.Printf("Starting TUI Parser on port %d", *port)

	// Create session manager
	sessionManager := session.NewManager()

	// Create WebSocket server
	wsServer := server.NewServer(sessionManager)
	go wsServer.Run()

	// Periodically refresh session list
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()

		for range ticker.C {
			wsServer.BroadcastSessionList()
		}
	}()

	// HTTP routes
	http.HandleFunc("/ws", wsServer.HandleWebSocket)

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		if _, err := w.Write([]byte("OK")); err != nil {
			log.Printf("health response: %v", err)
		}
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		if _, err := w.Write([]byte(`<!DOCTYPE html>
<html>
<head>
    <title>TUI Parser</title>
    <style>
        body { font-family: -apple-system, sans-serif; padding: 20px; background: #1a1a1a; color: #fff; }
        h1 { color: #4a9; }
        pre { background: #222; padding: 10px; border-radius: 4px; overflow-x: auto; }
        #output { height: 400px; overflow-y: auto; font-family: monospace; font-size: 12px; white-space: pre-wrap; }
        #sessions { margin-bottom: 20px; }
        button { background: #4a9; color: #fff; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin: 2px; }
        button:hover { background: #3a8; }
        input { padding: 8px; border-radius: 4px; border: 1px solid #444; background: #222; color: #fff; }
    </style>
</head>
<body>
    <h1>TUI Parser Debug Console</h1>
    <div id="sessions">
        <strong>Sessions:</strong> <span id="session-list">Loading...</span>
    </div>
    <div>
        <input type="text" id="session-input" placeholder="Session name" value="">
        <button onclick="subscribe()">Subscribe</button>
        <button onclick="sendKey('y')">Y</button>
        <button onclick="sendKey('n')">N</button>
        <button onclick="sendKey('enter')">Enter</button>
        <button onclick="sendKey('up')">Up</button>
        <button onclick="sendKey('down')">Down</button>
    </div>
    <h3>Output</h3>
    <pre id="output"></pre>

    <script>
        const ws = new WebSocket('ws://' + location.host + '/ws');
        const output = document.getElementById('output');
        const sessionList = document.getElementById('session-list');
        let currentSession = '';

        ws.onmessage = (event) => {
            const msg = JSON.parse(event.data);
            if (msg.type === 'sessions') {
                sessionList.textContent = msg.sessions.map(s => s.name + ' (' + s.status + ')').join(', ') || 'None';
            } else if (msg.type === 'output') {
                output.textContent += msg.text;
                output.scrollTop = output.scrollHeight;
            } else if (msg.type === 'prompt' || msg.type === 'menu') {
                output.textContent += '\n[DETECTED: ' + msg.type + ']\n';
            }
        };

        function subscribe() {
            currentSession = document.getElementById('session-input').value;
            if (currentSession) {
                ws.send(JSON.stringify({type: 'subscribe', sessionIds: [currentSession]}));
                output.textContent = 'Subscribed to: ' + currentSession + '\n';
            }
        }

        function sendKey(key) {
            if (currentSession) {
                ws.send(JSON.stringify({type: 'key', sessionId: currentSession, key: key}));
            }
        }
    </script>
</body>
</html>`)); err != nil {
			log.Printf("console response: %v", err)
		}
	})

	// Start HTTP server
	addr := fmt.Sprintf(":%d", *port)
	server := &http.Server{
		Addr:         addr,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Handle shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		log.Println("Shutting down...")
		sessionManager.Close()
		if err := server.Close(); err != nil {
			log.Printf("server close: %v", err)
		}
	}()

	log.Printf("Server listening on http://localhost%s", addr)
	log.Printf("WebSocket endpoint: ws://localhost%s/ws", addr)
	log.Printf("Debug console: http://localhost%s/", addr)

	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("HTTP server error: %v", err)
	}
}
