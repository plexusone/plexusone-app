package main

import (
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/plexusone/nexus/tuiparser/internal/server"
	"github.com/plexusone/nexus/tuiparser/internal/session"
)

func main() {
	port := flag.Int("port", 9600, "WebSocket server port")
	host := flag.String("host", "127.0.0.1", "Address to listen on; a non-loopback host requires a token")
	tokenFlag := flag.String("token", "", "Token clients must present (default: $"+server.TokenEnvVar+")")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lshortfile)

	token := *tokenFlag
	if token == "" {
		token = os.Getenv(server.TokenEnvVar)
	}
	if err := server.ValidateListenConfig(*host, token); err != nil {
		if suggestion, genErr := server.GenerateToken(); genErr == nil {
			log.Printf("Suggested token: %s", suggestion)
		} else {
			log.Printf("Could not generate a suggested token: %v", genErr)
		}
		log.Fatal(err)
	}

	addr := net.JoinHostPort(*host, strconv.Itoa(*port))
	log.Printf("Starting TUI Parser on %s", addr)
	if token != "" {
		log.Printf("Token authentication enabled for /ws")
	} else {
		log.Printf("Token authentication disabled (loopback only)")
	}

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
	// The health check and the static debug console expose no session data;
	// /ws, which lists sessions and accepts input, requires the token.
	http.HandleFunc("/ws", server.RequireToken(token, wsServer.HandleWebSocket))

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
        // Pass ?token=... in this page's URL when the server requires a token.
        const token = new URLSearchParams(location.search).get('token');
        const scheme = location.protocol === 'https:' ? 'wss://' : 'ws://';
        const ws = new WebSocket(scheme + location.host + '/ws' + (token ? '?token=' + encodeURIComponent(token) : ''));
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
	httpServer := &http.Server{
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
		if err := httpServer.Close(); err != nil {
			log.Printf("server close: %v", err)
		}
	}()

	log.Printf("Server listening on http://%s", addr)
	log.Printf("WebSocket endpoint: ws://%s/ws", addr)
	log.Printf("Debug console: http://%s/", addr)

	if err := httpServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("HTTP server error: %v", err)
	}
}
