require "kemal"
require "../src/v4cr"
require "option_parser"

# --- Command-line options ---
device_path : String? = nil
jpeg_quality = 70
fps = 30
resolution = {1280_u32, 720_u32}

OptionParser.parse do |parser|
  parser.banner = "V4CR MJPEG Streaming Server"
  parser.on("-d DEVICE", "--device=DEVICE", "Video device path (e.g., /dev/video0)") { |device_arg| device_path = device_arg }
  parser.on("-q QUALITY", "--quality=QUALITY", "JPEG quality (1-100, default: 70)") { |quality_arg| jpeg_quality = quality_arg.to_i }
  parser.on("-f FPS", "--fps=FPS", "Frames per second (default: 30)") { |fps_arg| fps = fps_arg.to_i }
  parser.on("-r WxH", "--resolution=WxH", "Resolution (e.g., 1920x1080)") do |_|
    width, height = r.split('x').map(&.to_u32)
    resolution = {width, height}
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end

# Global variables for the streaming device
class StreamingServer
  @@device : V4cr::Device? = nil
  @@streaming_fiber : Fiber? = nil
  @@streaming_clients = [] of HTTP::Server::Context
  @@fps = 30

  # MJPEG streaming boundary
  BOUNDARY = "frame"

  def self.device
    @@device
  end

  def self.streaming_clients
    @@streaming_clients
  end

  def self.fps=(new_fps)
    @@fps = new_fps
  end

  # Find and initialize the video device
  def self.initialize_device(device_path : String?, resolution : {UInt32, UInt32})
    devices_to_check = if device_path
                         [device_path]
                       else
                         (0..9).map { |i| "/dev/video#{i}" }
                       end

    devices_to_check.each do |path|
      next unless File.exists?(path)

      begin
        test_device = V4cr::Device.new(path)
        test_device.open

        capability = test_device.query_capability
        if capability.video_capture?
          begin
            test_device.set_format(resolution[0], resolution[1], V4cr::LibV4L2::V4L2_PIX_FMT_MJPG)
            puts "Using device: #{path} (#{capability.card}) - MJPEG #{resolution[0]}x#{resolution[1]}"
            @@device = test_device
            return test_device
          rescue e
            puts "Device #{path} doesn't support MJPG at #{resolution[0]}x#{resolution[1]}"
            # List available formats
            puts "Available formats:"
            test_device.supported_formats.each do |format|
              puts "  - #{format.description}"
              test_device.supported_resolutions(format.pixelformat).each do |res|
                puts "    - #{res[:width]}x#{res[:height]}"
              end
            end
            test_device.close
          end
        else
          test_device.close
        end
      rescue e
        puts "Error with device #{path}: #{e.message}"
      end
    end

    nil
  end

  # Streaming fiber that captures frames and sends them to clients
  def self.start_streaming_fiber
    return if @@streaming_fiber

    @@streaming_fiber = spawn do
      loop do
        device = @@device
        break unless device

        begin
          # Dequeue a frame from the already-started streaming
          buffer = device.dequeue_buffer

          # Skip frames that are too small or invalid
          data = buffer.read_data
          valid_jpeg = buffer.bytesused >= 1000 && data[0] == 0xFF && data[1] == 0xD8 && data[-2] == 0xFF && data[-1] == 0xD9

          if valid_jpeg
            # Send frame to all connected clients
            clients_to_remove = [] of HTTP::Server::Context

            @@streaming_clients.each do |client|
              begin
                # Write MJPEG frame with boundary
                client.response.write("--#{BOUNDARY}\r\n".to_slice)
                client.response.write("Content-Type: image/jpeg\r\n".to_slice)
                client.response.write("Content-Length: #{buffer.bytesused}\r\n\r\n".to_slice)
                client.response.write(buffer.read_data)
                client.response.write("\r\n".to_slice)
                client.response.flush
              rescue e
                puts "Client disconnected: #{e.message}"
                clients_to_remove << client
              end
            end

            # Remove disconnected clients
            clients_to_remove.each do |client|
              @@streaming_clients.delete(client)
            end
          end

          # Always re-queue the buffer for next capture
          device.queue_buffer(buffer)
        rescue e
          puts "Streaming error: #{e.message}"
          sleep(1.second)
        end
      end
    end
  end

  def self.cleanup
    puts "Shutting down..."
    @@streaming_clients.clear

    device = @@device
    if device
      device.stop_streaming rescue nil
      device.close rescue nil
    end
  end
end

# --- Main application ---

# Initialize device on startup
device = StreamingServer.initialize_device(device_path, resolution)
unless device
  puts "No suitable video device found!"
  puts "This server requires a device that supports MJPG format."
  puts "If you have a device, try specifying it with -d /dev/videoX"
  exit(1)
end

# Set JPEG quality
begin
  device.jpeg_quality = jpeg_quality
  puts "JPEG quality set to #{jpeg_quality}"
rescue e
  puts "Could not set JPEG quality: #{e.message}"
end

# Set FPS
begin
  device.framerate = fps.to_u32
  puts "Target FPS set to #{fps}"
rescue e
  puts "Could not set framerate: #{e.message}"
end

# Start streaming
device.request_buffers(4)
device.buffer_manager.each { |buffer| device.queue_buffer(buffer) }
device.start_streaming
StreamingServer.start_streaming_fiber

puts "
V4CR MJPEG Streaming Server"
puts "==========================="
puts "Device: #{device.query_capability.card}"
puts "Format: #{device.format.format_name} #{device.format.width}x#{device.format.height}"
puts "Server starting on http://localhost:3100"
puts "Press Ctrl+C to exit."

# --- Kemal web server ---

# Main page
get "/" do
  <<-HTML
  <!DOCTYPE html>
  <html>
  <head>
    <title>V4CR MJPEG Stream</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        text-align: center;
        background-color: #f0f0f0;
        margin: 0;
        padding: 20px;
      }
      .container {
        max-width: 800px;
        margin: 0 auto;
        background: white;
        padding: 20px;
        border-radius: 8px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      }
      h1 { color: #333; }
      .video-container {
        margin: 20px 0;
        border: 2px solid #ddd;
        border-radius: 8px;
        display: inline-block;
        padding: 10px;
        background: #f9f9f9;
      }
      img {
        max-width: 100%;
        border-radius: 4px;
      }
      .info {
        margin-top: 20px;
        padding: 15px;
        background: #e8f4f8;
        border-radius: 4px;
        text-align: left;
      }
      .controls {
        margin: 20px 0;
      }
      button {
        background: #007bff;
        color: white;
        border: none;
        padding: 10px 20px;
        border-radius: 4px;
        cursor: pointer;
        margin: 0 5px;
      }
      button:hover {
        background: #0056b3;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>V4CR MJPEG Live Stream</h1>

      <div class="video-container">
        <img id="stream" src="/stream" alt="Live Video Stream">
      </div>

      <div class="controls">
        <button onclick="refreshStream()">Refresh Stream</button>
        <button onclick="toggleFullscreen()">Toggle Fullscreen</button>
      </div>

      <div class="info">
        <h3>Stream Information</h3>
        <p><strong>Device:</strong> #{device.query_capability.card}</p>
        <p><strong>Driver:</strong> #{device.query_capability.driver}</p>
        <p><strong>Format:</strong> #{device.format.format_name}</p>
        <p><strong>Resolution:</strong> #{device.format.width}x#{device.format.height}</p>
        <p><strong>Target FPS:</strong> #{fps}</p>
        <p><strong>JPEG Quality:</strong> #{jpeg_quality}</p>
        <p><strong>Connected Clients:</strong> <span id="client-count">0</span></p>
      </div>
    </div>

    <script>
      function refreshStream() {
        const img = document.getElementById('stream');
        const src = img.src;
        img.src = '';
        img.src = src + '?t=' + new Date().getTime();
      }

      function toggleFullscreen() {
        const img = document.getElementById('stream');
        if (img.requestFullscreen) {
          img.requestFullscreen();
        } else if (img.webkitRequestFullscreen) {
          img.webkitRequestFullscreen();
        } else if (img.msRequestFullscreen) {
          img.msRequestFullscreen();
        }
      }

      // Update client count periodically
      setInterval(function() {
        fetch('/status')
          .then(response => response.json())
          .then(data => {
            document.getElementById('client-count').textContent = data.clients;
          })
          .catch(error => console.log('Status update failed:', error));
      }, 2000);
    </script>
  </body>
  </html>
  HTML
end

# MJPEG stream endpoint
get "/stream" do |env|
  # Set MJPEG headers
  env.response.headers["Content-Type"] = "multipart/x-mixed-replace; boundary=#{StreamingServer::BOUNDARY}"
  env.response.headers["Cache-Control"] = "no-cache"
  env.response.headers["Connection"] = "keep-alive"

  # Add client to streaming list
  StreamingServer.streaming_clients << env

  puts "Client connected (#{StreamingServer.streaming_clients.size} total)"

  # Keep connection open
  begin
    loop { sleep(1.second) }
  rescue e
    puts "Client disconnected: #{e.message}"
  ensure
    StreamingServer.streaming_clients.delete(env)
    puts "Client removed (#{StreamingServer.streaming_clients.size} remaining)"
  end
end

# Status endpoint
get "/status" do |env|
  env.response.content_type = "application/json"
  {
    clients: StreamingServer.streaming_clients.size,
    device:  StreamingServer.device.try(&.query_capability.card) || "Unknown",
    format:  StreamingServer.device.try(&.format.format_name) || "Unknown",
  }.to_json
end

# Cleanup on exit
at_exit do
  StreamingServer.cleanup
end

# Handle Ctrl+C gracefully
Process.on_terminate do
  puts "\nReceived interrupt signal, shutting down..."
  StreamingServer.cleanup
  exit(0)
end

Kemal.run(port: 3100)
