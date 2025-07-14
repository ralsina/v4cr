require "../src/v4cr"

# Example: List all supported formats, resolutions, and framerates for a device
def list_all_formats(device_path : String)
  unless File.exists?(device_path)
    puts "No video device found at #{device_path}"
    return
  end

  begin
    device = V4cr::Device.new(device_path)
    device.open

    capability = device.query_capability
    puts "Device: #{capability.card}"

    formats = device.supported_formats
    if formats.empty?
      puts "No supported formats found."
      device.close
      return
    end

    puts "Supported Formats:"
    formats.each do |format|
      puts "  #{format.format_name} - #{format.description}"
      resolutions = device.supported_resolutions(format.pixelformat)
      resolutions.each do |res|
        puts "    #{res[:width]}x#{res[:height]}"
      end
    end

    device.close
  rescue e : V4cr::DeviceError
    puts "Device error: #{e.message}"
  rescue e : V4cr::Error
    puts "V4CR error: #{e.message}"
  end
end

# Get device path from command line argument or use default
device_path = ARGV.size > 0 ? ARGV[0] : "/dev/video1"

list_all_formats(device_path)
