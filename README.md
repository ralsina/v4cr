# V4CR - Video4Linux2 Crystal Library

A Crystal language wrapper for the Video4Linux2 (V4L2) API, providing easy access to video capture devices on Linux systems.

## Features

- **Device Enumeration** - List and query video devices and their capabilities
- **Format Management** - Get and set video formats, enumerate supported formats
- **Multiple Formats** - Support for MJPEG (compressed) and raw formats like YUYV
- **Frame Capture** - Capture single frames or continuous streaming
- **Buffer Management** - Efficient memory-mapped buffer handling
- **JPEG Output** - Automatic JPEG file saving for MJPEG format
- **Error Handling** - Comprehensive error handling with custom exceptions
- **Type Safety** - Full Crystal type safety with proper structure definitions

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     v4cr:
       github: ralsina/v4cr
   ```

2. Run `shards install`

## Usage

```crystal
require "v4cr"

# Open a video device
device = V4cr::Device.new("/dev/video0")
device.open

# Query device capabilities
capability = device.query_capability
puts "Device: #{capability.card}"
puts "Supports capture: #{capability.video_capture?}"

# Set video format (tries MJPEG first, falls back to YUYV)
format = device.set_format(640, 480, V4cr::LibV4L2::V4L2_PIX_FMT_MJPEG)
puts "Format: #{format.format_name} #{format.width}x#{format.height}"

# Capture a single frame
buffer = device.capture_frame
puts "Captured #{buffer.data.size} bytes"

# Clean up
device.close
```

## Demo Application

The library includes a comprehensive demo application showcasing all features:

```bash
# Auto-select a capture device
crystal run examples/demo.cr

# Use a specific device
crystal run examples/demo.cr -- /dev/video1

# Show help
crystal run examples/demo.cr -- --help
```

The demo provides an interactive menu with options for:
1. Device enumeration and capability listing
2. Single frame capture
3. Streaming video capture
4. Frame saving to files
5. All examples in sequence

## API Overview

### Core Classes

- **`V4cr::Device`** - Main interface for video devices
- **`V4cr::Capability`** - Device capability information
- **`V4cr::Format`** - Video format description
- **`V4cr::Buffer`** - Frame data buffer
- **`V4cr::BufferManager`** - Manages multiple buffers for streaming

### Key Methods

- `Device#open` / `Device#close` - Device lifecycle management
- `Device#query_capability` - Get device capabilities
- `Device#supported_formats` - List supported video formats
- `Device#set_format` / `Device#get_format` - Format management
- `Device#capture_frame` - Single frame capture
- `Device#request_buffers` - Set up streaming buffers
- `Device#start_streaming` / `Device#stop_streaming` - Streaming control
- `Device#queue_buffer` / `Device#dequeue_buffer` - Buffer management

## Requirements

- Crystal 1.0+
- Linux with V4L2 support
- Video capture device (USB webcam, etc.)

## Development

After checking out the repo, run:

```bash
shards install
crystal spec
```

To run the demo:

```bash
crystal run examples/demo.cr
```

## Testing

The library includes comprehensive tests covering:
- Structure size validation
- Device operations
- Format handling
- Buffer management

Run tests with:

```bash
crystal spec
```

## Contributing

1. Fork it (<https://github.com/ralsina/v4cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [ralsina](https://github.com/ralsina) - creator and maintainer
