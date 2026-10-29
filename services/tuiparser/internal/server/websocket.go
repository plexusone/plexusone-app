package server

import (
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/plexusone/nexus/tuiparser/internal/session"
	"github.com/plexusone/nexus/tuiparser/pkg/protocol"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for local use
	},
}

// Client represents a connected WebSocket client
type Client struct {
	conn          *websocket.Conn
	server        *Server
	subscriptions map[string]bool
	send          chan []byte
	mu            sync.Mutex
}

// Server handles WebSocket connections and message routing
type Server struct {
	sessionManager *session.Manager
	clients        map[*Client]bool
	broadcast      chan *BroadcastMessage
	register       chan *Client
	unregister     chan *Client
	mu             sync.RWMutex
}

// BroadcastMessage is a message to send to subscribed clients
type BroadcastMessage struct {
	SessionID string
	Data      []byte
}

// NewServer creates a new WebSocket server
func NewServer(sessionManager *session.Manager) *Server {
	s := &Server{
		sessionManager: sessionManager,
		clients:        make(map[*Client]bool),
		broadcast:      make(chan *BroadcastMessage, 256),
		register:       make(chan *Client),
		unregister:     make(chan *Client),
	}

	// Set up session manager callbacks
	sessionManager.OnOutput = func(sessionID string, data []byte) {
		msg := protocol.NewOutputMessage(sessionID, string(data))
		jsonData, err := json.Marshal(msg)
		if err != nil {
			log.Printf("Error marshaling output: %v", err)
			return
		}
		s.broadcast <- &BroadcastMessage{SessionID: sessionID, Data: jsonData}
	}

	sessionManager.OnStatus = func(sessionID string, status string) {
		msg := protocol.NewStatusMessage(sessionID, status)
		jsonData, err := json.Marshal(msg)
		if err != nil {
			log.Printf("Error marshaling status: %v", err)
			return
		}
		s.broadcast <- &BroadcastMessage{SessionID: sessionID, Data: jsonData}
	}

	return s
}

// Run starts the server's main loop
func (s *Server) Run() {
	for {
		select {
		case client := <-s.register:
			s.mu.Lock()
			s.clients[client] = true
			s.mu.Unlock()

			// Send current session list
			go s.sendSessionList(client)

		case client := <-s.unregister:
			s.mu.Lock()
			if _, ok := s.clients[client]; ok {
				delete(s.clients, client)
				close(client.send)
			}
			s.mu.Unlock()

		case message := <-s.broadcast:
			s.mu.RLock()
			for client := range s.clients {
				// Only send to clients subscribed to this session
				client.mu.Lock()
				subscribed := message.SessionID == "" || client.subscriptions[message.SessionID]
				client.mu.Unlock()

				if subscribed {
					select {
					case client.send <- message.Data:
					default:
						// Client buffer full, skip
					}
				}
			}
			s.mu.RUnlock()
		}
	}
}

// sendSessionList sends the current session list to a client
func (s *Server) sendSessionList(client *Client) {
	sessions, err := s.sessionManager.ListTmuxSessions()
	if err != nil {
		log.Printf("Error listing sessions: %v", err)
		return
	}

	msg := protocol.NewSessionsMessage(sessions)
	jsonData, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error marshaling sessions: %v", err)
		return
	}

	select {
	case client.send <- jsonData:
	default:
	}
}

// BroadcastSessionList sends session list to all clients
func (s *Server) BroadcastSessionList() {
	sessions, err := s.sessionManager.ListTmuxSessions()
	if err != nil {
		log.Printf("Error listing sessions: %v", err)
		return
	}

	msg := protocol.NewSessionsMessage(sessions)
	jsonData, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error marshaling sessions: %v", err)
		return
	}

	s.broadcast <- &BroadcastMessage{SessionID: "", Data: jsonData}
}

// HandleWebSocket handles WebSocket connection upgrades
func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	client := &Client{
		conn:          conn,
		server:        s,
		subscriptions: make(map[string]bool),
		send:          make(chan []byte, 256),
	}

	s.register <- client

	go client.writePump()
	go client.readPump()
}

// readPump reads messages from the WebSocket connection
func (c *Client) readPump() {
	defer func() {
		c.server.unregister <- c
		c.closeConn()
	}()

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			return
		}

		c.handleMessage(message)
	}
}

// closeConn closes the connection. readPump and writePump both close it
// when they end, so the second close reports an already-closed connection,
// which is expected and not logged.
func (c *Client) closeConn() {
	if err := c.conn.Close(); err != nil && !errors.Is(err, net.ErrClosed) {
		log.Printf("WebSocket close: %v", err)
	}
}

// writePump writes messages to the WebSocket connection
func (c *Client) writePump() {
	defer c.closeConn()

	for message := range c.send {
		if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
			return
		}
	}
}

// handleMessage processes incoming client messages
func (c *Client) handleMessage(data []byte) {
	var base protocol.BaseMessage
	if err := json.Unmarshal(data, &base); err != nil {
		log.Printf("Error parsing message: %v", err)
		return
	}

	switch base.Type {
	case protocol.TypeList:
		// Send session list to this client
		c.server.sendSessionList(c)

	case protocol.TypeSubscribe:
		var msg protocol.SubscribeMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("Error parsing subscribe: %v", err)
			return
		}
		c.handleSubscribe(msg.SessionIDs)

	case protocol.TypeUnsubscribe:
		var msg protocol.UnsubscribeMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("Error parsing unsubscribe: %v", err)
			return
		}
		c.handleUnsubscribe(msg.SessionIDs)

	case protocol.TypeInput:
		var msg protocol.InputMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("Error parsing input: %v", err)
			return
		}
		c.handleInput(msg.SessionID, msg.Text)

	case protocol.TypeKey:
		var msg protocol.KeyMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("Error parsing key: %v", err)
			return
		}
		c.handleKey(msg.SessionID, msg.Key)

	case protocol.TypeAction:
		var msg protocol.ActionMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("Error parsing action: %v", err)
			return
		}
		c.handleAction(msg.SessionID, msg.Action, msg.Value)
	}
}

// handleSubscribe subscribes to sessions
func (c *Client) handleSubscribe(sessionIDs []string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	for _, id := range sessionIDs {
		c.subscriptions[id] = true

		// Attach to the session if not already attached
		_, err := c.server.sessionManager.Attach(id)
		if err != nil {
			log.Printf("Error attaching to session %s: %v", id, err)
			// Send error to client
			errMsg := protocol.NewErrorMessage(id, err.Error())
			jsonData, _ := json.Marshal(errMsg)
			select {
			case c.send <- jsonData:
			default:
			}
		}
	}
}

// handleUnsubscribe unsubscribes from sessions
func (c *Client) handleUnsubscribe(sessionIDs []string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	for _, id := range sessionIDs {
		delete(c.subscriptions, id)
	}
}

// handleInput sends text input to a session
func (c *Client) handleInput(sessionID, text string) {
	if err := c.server.sessionManager.SendInput(sessionID, text); err != nil {
		log.Printf("Error sending input to %s: %v", sessionID, err)
	}
}

// handleKey sends a special key to a session
func (c *Client) handleKey(sessionID, key string) {
	if err := c.server.sessionManager.SendKey(sessionID, key); err != nil {
		log.Printf("Error sending key to %s: %v", sessionID, err)
	}
}

// handleAction handles prompt/menu/wizard actions
func (c *Client) handleAction(sessionID, action, value string) {
	// For now, translate actions to keystrokes
	switch action {
	case "yes", "y":
		c.sendKeys(sessionID, "y", "enter")
	case "no", "n":
		c.sendKeys(sessionID, "n", "enter")
	case "always", "a":
		c.sendKeys(sessionID, "a", "enter")
	case "submit", "enter":
		c.sendKeys(sessionID, "enter")
	case "cancel", "escape":
		c.sendKeys(sessionID, "escape")
	case "select":
		// Value contains the selection, send it
		if value != "" {
			if err := c.server.sessionManager.SendInput(sessionID, value); err != nil {
				log.Printf("Error sending input to %s: %v", sessionID, err)
				return
			}
			c.sendKeys(sessionID, "enter")
		}
	}
}

// sendKeys sends keys in order, stopping at the first failure, which is logged.
func (c *Client) sendKeys(sessionID string, keys ...string) {
	for _, key := range keys {
		if err := c.server.sessionManager.SendKey(sessionID, key); err != nil {
			log.Printf("Error sending key %q to %s: %v", key, sessionID, err)
			return
		}
	}
}
