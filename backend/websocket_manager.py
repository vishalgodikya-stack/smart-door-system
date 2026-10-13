"""
websocket_manager.py — Manages all active WebSocket connections and broadcasts events
Smart Door Security System
"""
import json
from typing import Any

from fastapi import WebSocket


class ConnectionManager:
    """Keeps track of all connected WebSocket clients and broadcasts events."""

    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"[WS] Client connected. Total: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        print(f"[WS] Client disconnected. Total: {len(self.active_connections)}")

    async def broadcast(self, event: str, data: Any):
        """Send an event + data payload to all connected clients."""
        message = json.dumps({"event": event, "data": data}, default=str)
        dead = []
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception:
                dead.append(connection)
        for d in dead:
            self.active_connections.remove(d)

    async def send_to(self, websocket: WebSocket, event: str, data: Any):
        """Send an event to a single client."""
        message = json.dumps({"event": event, "data": data}, default=str)
        await websocket.send_text(message)


# Global instance shared across all routers
manager = ConnectionManager()
