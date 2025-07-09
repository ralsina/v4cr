# V4CR MJPEG Streaming Server

A real-time video streaming server built with Crystal, Kemal, and the V4CR library. This server captures video from V4L2 devices and serves it as an MJPEG stream over HTTP.

## Features

- **Real-time MJPEG streaming** - Live video feed accessible via web browser
- **Auto device detection** - Automatically finds the first available capture device
- **Multiple format support** - Tries MJPEG first, falls back to YUYV if needed
- **Multiple resolution support** - Tests different resolutions to find the best fit
- **Web interface** - Clean HTML interface with stream controls
- **Client management** - Tracks connected clients and handles disconnections
- **Status API** - Real-time status information via JSON API

## Running the Server

```bash
# Install dependencies
shards install

# Start the server
crystal run examples/streaming_server.cr

# Server will start on http://localhost:3000
```

## Endpoints

### GET /
Main web interface with live video stream and controls.

### GET /stream
MJPEG stream endpoint. Returns:
- Content-Type: `multipart/x-mixed-replace; boundary=frame`
- Continuous MJPEG frames at ~30 FPS

### GET /status
JSON status endpoint returning:
```json
{
  "clients": 1,
  "device": "USB Video: USB Video", 
  "format": "MJPG"
}
```

## Web Interface Features

- **Live video stream** - Real-time MJPEG display
- **Stream controls** - Refresh stream, toggle fullscreen
- **Device information** - Shows device details and current format
- **Client counter** - Live count of connected streaming clients

## Technical Details

### Format Selection
The server tries formats in this order:
1. MJPEG at various resolutions (320x240, 640x480, 800x600, 1024x768)
2. YUYV at 640x480 (fallback)

### Frame Rate
- Target: ~30 FPS (33ms delay between frames)
- Actual rate depends on device capabilities and system performance

### Buffer Management
- Uses 4 memory-mapped buffers for efficient frame capture
- Automatic buffer queuing/dequeuing
- Proper cleanup on client disconnections

### Client Management
- Tracks all connected streaming clients
- Handles client disconnections gracefully
- Broadcasts each frame to all connected clients simultaneously

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   V4L2 Device   │───▶│  V4CR Library   │───▶│ Streaming Server│
│  (USB Camera)   │    │  (Buffer Mgmt)  │    │  (Kemal/HTTP)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                      │
                                                      ▼
                                              ┌─────────────────┐
                                              │  Web Browsers   │
                                              │  (MJPEG Stream) │
                                              └─────────────────┘
```

## Example Usage

```bash
# Start server
crystal run examples/streaming_server.cr

# Open browser to http://localhost:3000
# Multiple clients can connect simultaneously
# Each client receives the same live stream
```

## Error Handling

- **Device not found**: Server exits with error message
- **Format not supported**: Falls back to alternative formats
- **Client disconnection**: Automatically removes client from broadcast list
- **Stream errors**: Automatically retries with 1-second delay

## Performance Notes

- MJPEG format provides good compression (~15-20KB per frame)
- Raw YUYV format uses more bandwidth (~600KB per frame)
- Frame rate adjusts automatically based on system performance
- Memory usage stays constant with buffer reuse

This streaming server demonstrates real-world usage of the V4CR library for video streaming applications.
