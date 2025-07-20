module V4cr
  # Represents a pixel format supported by a V4L2 device
  class Format
    getter index : UInt32
    getter description : String
    getter pixelformat : UInt32
    getter flags : UInt32
    getter width : UInt32?
    getter height : UInt32?
    getter bytesperline : UInt32?
    getter sizeimage : UInt32?

    def initialize(@index : UInt32, @description : String, @pixelformat : UInt32, @flags : UInt32)
      @width = nil
      @height = nil
      @bytesperline = nil
      @sizeimage = nil
    end

    def initialize(@index : UInt32, @description : String, @pixelformat : UInt32, @flags : UInt32,
                   @width : UInt32, @height : UInt32, @bytesperline : UInt32, @sizeimage : UInt32)
    end

    # Get the four-character code (fourcc) as a string
    def fourcc
      fourcc_to_string(@pixelformat)
    end

    # Get format name from pixel format constant
    def format_name
      case @pixelformat
      when LibV4L2::V4L2_PIX_FMT_RGB332
        "RGB332"
      when LibV4L2::V4L2_PIX_FMT_RGB565
        "RGB565"
      when LibV4L2::V4L2_PIX_FMT_RGB24
        "RGB24"
      when LibV4L2::V4L2_PIX_FMT_RGB32
        "RGB32"
      when LibV4L2::V4L2_PIX_FMT_YUYV
        "YUYV"
      when LibV4L2::V4L2_PIX_FMT_UYVY
        "UYVY"
      when LibV4L2::V4L2_PIX_FMT_YUV420
        "YUV420"
      when LibV4L2::V4L2_PIX_FMT_YUV422P
        "YUV422P"
      when LibV4L2::V4L2_PIX_FMT_MJPG
        "MJPG"
      when LibV4L2::V4L2_PIX_FMT_JPEG
        "JPEG"
      else
        fourcc
      end
    end

    # Check if this is a compressed format
    def compressed?
      @flags & 0x0001 != 0
    end

    # Check if this is an emulated format (converted by libv4l2)
    def emulated?
      @flags & 0x0002 != 0
    end

    # Set dimensions and calculate buffer parameters
    def set_dimensions(@width : UInt32, @height : UInt32)
      @bytesperline = calculate_bytesperline(@width, @pixelformat)
      @sizeimage = calculate_sizeimage(@width, @height, @pixelformat)
    end

    def to_s(io)
      io << "Format(#{format_name}, #{@width}x#{@height}" if @width && @height
      io << "Format(#{format_name}" unless @width && @height
      io << ", #{@description}, compressed: #{compressed?}, emulated: #{emulated?})"
    end

    private def fourcc_to_string(fourcc : UInt32)
      String.new(4) do |buffer|
        buffer[0] = (fourcc & 0xFF).to_u8
        buffer[1] = ((fourcc >> 8) & 0xFF).to_u8
        buffer[2] = ((fourcc >> 16) & 0xFF).to_u8
        buffer[3] = ((fourcc >> 24) & 0xFF).to_u8
        {4, 4}
      end
    end

    private def calculate_bytesperline(width : UInt32, pixelformat : UInt32) : UInt32
      case pixelformat
      when LibV4L2::V4L2_PIX_FMT_RGB332
        width
      when LibV4L2::V4L2_PIX_FMT_RGB565
        width * 2
      when LibV4L2::V4L2_PIX_FMT_RGB24
        width * 3
      when LibV4L2::V4L2_PIX_FMT_RGB32
        width * 4
      when LibV4L2::V4L2_PIX_FMT_YUYV, LibV4L2::V4L2_PIX_FMT_UYVY
        width * 2
      when LibV4L2::V4L2_PIX_FMT_YUV420
        width
      when LibV4L2::V4L2_PIX_FMT_YUV422P
        width
      else
        width * 2 # Default assumption
      end
    end

    private def calculate_sizeimage(width : UInt32, height : UInt32, pixelformat : UInt32) : UInt32
      case pixelformat
      when LibV4L2::V4L2_PIX_FMT_RGB332
        width * height
      when LibV4L2::V4L2_PIX_FMT_RGB565
        width * height * 2
      when LibV4L2::V4L2_PIX_FMT_RGB24
        width * height * 3
      when LibV4L2::V4L2_PIX_FMT_RGB32
        width * height * 4
      when LibV4L2::V4L2_PIX_FMT_YUYV, LibV4L2::V4L2_PIX_FMT_UYVY
        width * height * 2
      when LibV4L2::V4L2_PIX_FMT_YUV420
        (width * height * 3) // 2
      when LibV4L2::V4L2_PIX_FMT_YUV422P
        width * height * 2
      when LibV4L2::V4L2_PIX_FMT_MJPG, LibV4L2::V4L2_PIX_FMT_JPEG
        width * height # Compressed format, estimate
      else
        width * height * 2 # Default assumption
      end
    end
  end
end
