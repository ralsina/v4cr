module V4cr
  # Represents the capabilities of a V4L2 device
  class Capability
    getter driver : String
    getter card : String
    getter bus_info : String
    getter version : UInt32
    getter capabilities : UInt32
    getter device_caps : UInt32

    def initialize(@driver : String, @card : String, @bus_info : String,
                   @version : UInt32, @capabilities : UInt32, @device_caps : UInt32)
    end

    # Check if the device supports video capture
    def video_capture?
      (@capabilities & LibV4L2::V4L2_CAP_VIDEO_CAPTURE) != 0
    end

    # Check if the device supports video output
    def video_output?
      (@capabilities & LibV4L2::V4L2_CAP_VIDEO_OUTPUT) != 0
    end

    # Check if the device supports video overlay
    def video_overlay?
      (@capabilities & LibV4L2::V4L2_CAP_VIDEO_OVERLAY) != 0
    end

    # Check if the device supports streaming I/O
    def streaming?
      (@capabilities & LibV4L2::V4L2_CAP_STREAMING) != 0
    end

    # Check if the device supports read/write I/O
    def readwrite?
      (@capabilities & LibV4L2::V4L2_CAP_READWRITE) != 0
    end

    # Get version as a human-readable string
    def version_string
      major = (@version >> 16) & 0xFF
      minor = (@version >> 8) & 0xFF
      patch = @version & 0xFF
      "#{major}.#{minor}.#{patch}"
    end

    def to_s(io)
      io << "Capability(driver: #{@driver}, card: #{@card}, "
      io << "bus_info: #{@bus_info}, version: #{version_string}, "
      io << "capture: #{video_capture?}, output: #{video_output?}, "
      io << "overlay: #{video_overlay?}, streaming: #{streaming?}, "
      io << "readwrite: #{readwrite?})"
    end
  end
end
