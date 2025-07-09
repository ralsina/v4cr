# V4CR Examples

This directory contains example programs demonstrating the V4CR (Video4Linux2 Crystal) library.

## Demo Application

The main demo application (`demo.cr`) showcases all the key features of the V4CR library:

### Running the Demo

```bash
# Auto-select a capture device
crystal run examples/demo.cr

# Use a specific device
crystal run examples/demo.cr -- /dev/video1

# Show help
crystal run examples/demo.cr -- --help
```

### Features Demonstrated

1. **Device Enumeration** - Lists all available video devices with their capabilities
2. **Single Frame Capture** - Captures a single frame from the device
3. **Streaming** - Demonstrates continuous frame capture using V4L2 streaming
4. **Frame Saving** - Saves captured frames to files for analysis

### Example Output

The demo will automatically detect capture-capable devices and provide an interactive menu:

```
V4CR Examples
=============
Auto-selected capture device: /dev/video1

1. List devices
2. Capture single frame
3. Streaming example
4. Save frames to files
5. All examples

Select an option (1-5):
```

### Device Requirements

The demo requires a V4L2-compatible video device that supports:
- Video capture capability
- Streaming I/O
- YUYV or MJPEG pixel formats (common formats)

### File Output

When using the "Save frames to files" option:
- **MJPEG format**: Frames are saved as `.jpg` files (already compressed JPEG images)
- **Raw formats**: Frames are saved as `.raw` files containing raw pixel data

The demo automatically tries MJPEG format first and falls back to YUYV if not supported. MJPEG frames are much smaller (15-20KB) compared to raw YUYV frames (600KB+) due to compression.

### Troubleshooting

- **No capture devices found**: Make sure you have a USB webcam or other V4L2 device connected
- **Permission denied**: You may need to run with sudo or add your user to the video group
- **Format not supported**: The demo tries common formats, but some devices may require different pixel formats

### Understanding the Output

- **Size**: Number of bytes in the captured frame
- **Sequence**: Frame sequence number from the device
- **Timestamp**: When the frame was captured (may be relative to device start)
- **Frame data preview**: First few bytes of the frame data in hexadecimal

This demonstrates the full capabilities of the V4CR library for video capture applications.
