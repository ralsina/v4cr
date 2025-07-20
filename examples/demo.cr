require "../src/v4cr"

# V4CR Demo Application
# This demo showcases the capabilities of the V4CR (Video4Linux2 Crystal) library
# It demonstrates device enumeration, format detection, single frame capture,
# streaming, and frame saving functionality.

# Check for help argument
if ARGV.includes?("-h") || ARGV.includes?("--help")
  puts "Usage: crystal run examples/demo.cr -- [device_path]"
  puts
  puts "Examples:"
  puts "  crystal run examples/demo.cr                    # Auto-select capture device"
  puts "  crystal run examples/demo.cr -- /dev/video1     # Use specific device"
  puts
  puts "Options:"
  puts "  -h, --help                                     Show this help message"
  puts
  puts "Note: Use '--' to separate Crystal compiler options from program arguments"
  exit(0)
end

# Get device path from command line argument or use default
device_path = ARGV.size > 0 ? ARGV[0] : "/dev/video0"

# Find the first available capture device
def find_capture_device
  0.upto(9) do |i|
    device_path = "/dev/video#{i}"
    next unless File.exists?(device_path)

    begin
      device = V4cr::Device.new(device_path)
      device.open

      capability = device.query_capability
      if capability.video_capture?
        device.close
        return device_path
      end

      device.close
    rescue e : V4cr::DeviceError
      # Continue to next device
    end
  end

  nil
end

# Example: List all video devices and their capabilities
def list_devices
  puts "Scanning for video devices..."

  0.upto(9) do |i|
    device_path = "/dev/video#{i}"
    next unless File.exists?(device_path)

    begin
      device = V4cr::Device.new(device_path)
      device.open

      capability = device.query_capability
      puts "\nDevice: #{device_path}"
      puts "  Card: #{capability.card}"
      puts "  Driver: #{capability.driver}"
      puts "  Bus Info: #{capability.bus_info}"
      puts "  Version: #{capability.version_string}"
      puts "  Capabilities:"
      puts "    Video Capture: #{capability.video_capture?}"
      puts "    Video Output: #{capability.video_output?}"
      puts "    Streaming: #{capability.streaming?}"
      puts "    Read/Write: #{capability.readwrite?}"

      # List supported formats
      formats = device.supported_formats
      if !formats.empty?
        puts "  Supported Formats:"
        formats.each do |format|
          puts "    #{format.format_name} - #{format.description}"
        end
      end

      # List inputs
      inputs = device.inputs
      if !inputs.empty?
        puts "  Inputs:"
        inputs.each_with_index do |input, idx|
          marker = idx == device.current_input ? "*" : " "
          puts "  #{marker} #{idx}: #{input}"
        end
      end

      device.close
    rescue e : V4cr::DeviceError
      puts "  Error: #{e.message}"
    end
  end
end

# Example: Capture a frame from the specified device
def capture_example(device_path : String)
  unless File.exists?(device_path)
    puts "No video device found at #{device_path}"
    return
  end

  begin
    device = V4cr::Device.new(device_path)
    device.open

    capability = device.query_capability
    puts "Capturing from: #{capability.card}"

    # Check if device supports capture
    unless capability.video_capture?
      puts "Device does not support video capture"
      device.close
      return
    end

    # Try MJPEG first, fall back to YUYV
    format = begin
      device.set_format(640, 480, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)
    rescue
      device.set_format(640, 480, V4cr::LibV4L2::V4L2_PIX_FMT_YUYV)
    end
    puts "Format set to: #{format.format_name} #{format.width}x#{format.height}"

    # Capture a frame
    puts "Capturing frame..."
    buffer = device.capture_frame

    puts "Captured frame:"
    puts "  Size: #{buffer.data.size} bytes"
    puts "  Sequence: #{buffer.sequence}"

    # Better timestamp formatting
    if buffer.timestamp.year > 2000
      puts "  Timestamp: #{buffer.timestamp.to_s("%Y-%m-%d %H:%M:%S")}"
    else
      puts "  Timestamp: #{buffer.timestamp} (relative)"
    end

    # Show some basic frame info
    if buffer.data.size > 0
      puts "  Frame data preview: #{buffer.data[0...[10, buffer.data.size].min].map(&.to_s(16)).join(" ")}"
    end

    device.close
  rescue e : V4cr::DeviceError
    puts "Device error: #{e.message}"
  rescue e : V4cr::Error
    puts "V4CR error: #{e.message}"
  end
end

# Example: Streaming from device
def streaming_example(device_path : String)
  unless File.exists?(device_path)
    puts "No video device found at #{device_path}"
    return
  end

  begin
    device = V4cr::Device.new(device_path)
    device.open

    capability = device.query_capability
    puts "Streaming from: #{capability.card}"

    # Check if device supports capture
    unless capability.video_capture?
      puts "Device does not support video capture"
      device.close
      return
    end

    # Try MJPEG first, fall back to YUYV
    format = begin
      device.set_format(320, 240, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)
    rescue
      device.set_format(320, 240, V4cr::LibV4L2::V4L2_PIX_FMT_YUYV)
    end
    puts "Format: #{format.format_name} #{format.width}x#{format.height}"

    # Request buffers
    buffer_manager = device.request_buffers(4)
    puts "Requested #{buffer_manager.size} buffers"

    # Queue all buffers
    buffer_manager.each do |buffer|
      device.queue_buffer(buffer)
    end

    # Start streaming
    device.start_streaming
    puts "Streaming started, capturing 10 frames..."

    # Capture frames
    10.times do |i|
      buffer = device.dequeue_buffer
      puts "Frame #{i + 1}: #{buffer.data.size} bytes, sequence: #{buffer.sequence}"

      # Re-queue the buffer
      device.queue_buffer(buffer)
    end

    # Stop streaming
    device.stop_streaming
    puts "Streaming stopped"

    device.close
  rescue e : V4cr::DeviceError
    puts "Device error: #{e.message}"
  rescue e : V4cr::Error
    puts "V4CR error: #{e.message}"
  end
end

# Example: Save captured frames to files
def save_frames_example(device_path : String, count : Int32 = 5000)
  unless File.exists?(device_path)
    puts "No video device found at #{device_path}"
    return
  end

  begin
    device = V4cr::Device.new(device_path)
    device.open

    capability = device.query_capability
    puts "Saving frames from: #{capability.card}"

    # Check if device supports capture
    unless capability.video_capture?
      puts "Device does not support video capture"
      device.close
      return
    end

    # Try MJPEG first, fall back to YUYV
    format = begin
      device.set_format(640, 480, V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)
    rescue
      device.set_format(640, 480, V4cr::LibV4L2::V4L2_PIX_FMT_YUYV)
    end
    puts "Format: #{format.format_name} #{format.width}x#{format.height}"

    # Request buffers
    buffer_manager = device.request_buffers(4)
    puts "Requested #{buffer_manager.size} buffers"

    # Queue all buffers
    buffer_manager.each do |buffer|
      device.queue_buffer(buffer)
    end

    # Start streaming
    device.start_streaming
    puts "Streaming started, capturing #{count} frames to files..."

    # Create output directory
    Dir.mkdir_p("captured_frames")

    # Capture frames
    count.times do |i|
      buffer = device.dequeue_buffer

      # Determine file extension and save appropriately
      if format.format_name == "MJPG"
        # MJPEG frames are already JPEG compressed
        filename = "captured_frames/frame_#{i.to_s.rjust(3, '0')}.jpg"
        File.write(filename, buffer.data)
        puts "Frame #{i + 1}: #{buffer.data.size} bytes saved to #{filename} (JPEG)"
      else
        # Raw format frames
        filename = "captured_frames/frame_#{i.to_s.rjust(3, '0')}.raw"
        File.write(filename, buffer.data)
        puts "Frame #{i + 1}: #{buffer.data.size} bytes saved to #{filename} (raw #{format.format_name})"
      end

      # Re-queue the buffer
      device.queue_buffer(buffer)
    end

    # Stop streaming
    device.stop_streaming
    puts "Streaming stopped"

    if format.format_name == "MJPG"
      puts "JPEG frames saved to captured_frames/ directory"
    else
      puts "Raw #{format.format_name} frames saved to captured_frames/ directory"
    end

    device.close
  rescue e : V4cr::DeviceError
    puts "Device error: #{e.message}"
  rescue e : V4cr::Error
    puts "V4CR error: #{e.message}"
  end
end

# Main menu
puts "V4CR Examples"
puts "============="

# If device path is provided, use it; otherwise try to find a capture device
if device_path == "/dev/video0"
  if capture_device = find_capture_device
    device_path = capture_device
    puts "Auto-selected capture device: #{device_path}"
  else
    puts "No capture devices found, using default: #{device_path}"
  end
else
  puts "Using specified device: #{device_path}"
end

puts
puts "1. List devices"
puts "2. Capture single frame"
puts "3. Streaming example"
puts "4. Save frames to files"
puts "5. All examples"
puts

# Get choice from command line or stdin
choice = if ARGV.size > 1
           ARGV[1] # If device path is provided, get choice from second argument
         else
           print "Select an option (1-5): "
           gets.try(&.strip)
         end

case choice
when "1"
  list_devices
when "2"
  capture_example(device_path)
when "3"
  streaming_example(device_path)
when "4"
  save_frames_example(device_path)
when "5"
  list_devices
  puts "\n" + "="*50 + "\n"
  capture_example(device_path)
  puts "\n" + "="*50 + "\n"
  streaming_example(device_path)
  puts "\n" + "="*50 + "\n"
  save_frames_example(device_path)
else
  puts "Invalid choice"
end
