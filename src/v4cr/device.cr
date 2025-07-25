module V4cr
  # Main class for interacting with V4L2 devices
  class Device
    getter device_path : String
    getter fd : Int32?
    getter capability : Capability?
    getter current_format : Format?
    getter buffer_manager : BufferManager

    def initialize(@device_path : String)
      @fd = nil
      @capability = nil
      @current_format = nil
      @buffer_manager = BufferManager.new(0, LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE, LibV4L2::V4L2_MEMORY_MMAP)
    end

    # Open the device
    def open
      raise DeviceError.new("Device already open") if @fd

      fd = LibC.open(@device_path, LibV4L2::O_RDWR | LibV4L2::O_NONBLOCK)
      raise DeviceError.new("Failed to open device: #{@device_path}") if fd < 0

      @fd = fd
      @capability = query_capability
    end

    # Close the device
    def close
      if @fd
        # Clean up buffers if they exist
        @buffer_manager.each do |buffer|
          if buffer.mmap_ptr != Pointer(Void).null
            LibC.munmap(buffer.mmap_ptr, buffer.length)
          end
        end
        @buffer_manager = BufferManager.new(0, LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE, LibV4L2::V4L2_MEMORY_MMAP)

        if @fd
          LibC.close(@fd.as(Int32))
        end
        @fd = nil
        @capability = nil
        @current_format = nil
      end
    end

    # Ensure the device is open
    private def ensure_open
      raise DeviceError.new("Device not open") unless @fd
    end

    # Query device capabilities
    def query_capability : Capability
      ensure_open

      cap = LibV4L2::V4l2Capability.new
      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_QUERYCAP, pointerof(cap))
      raise DeviceError.new("Failed to query capabilities") if result < 0

      driver = String.new(cap.driver.to_unsafe)
      card = String.new(cap.card.to_unsafe)
      bus_info = String.new(cap.bus_info.to_unsafe)

      Capability.new(driver, card, bus_info, cap.version, cap.capabilities, cap.device_caps)
    end

    # Get all supported formats
    def supported_formats : Array(Format)
      ensure_open

      formats = [] of Format
      index = 0_u32

      loop do
        fmt_desc = LibV4L2::V4l2FmtDesc.new
        fmt_desc.index = index
        fmt_desc.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE

        raise DeviceError.new("Device not open") unless @fd
        result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_ENUM_FMT, pointerof(fmt_desc))
        break if result < 0

        description = String.new(fmt_desc.description.to_unsafe)
        format = Format.new(fmt_desc.index, description, fmt_desc.pixelformat, fmt_desc.flags)
        formats << format

        index += 1
      end

      formats
    end

    def supported_resolutions(pixelformat : UInt32)
      ensure_open

      resolutions = [] of NamedTuple(width: UInt32, height: UInt32)
      index = 0_u32

      loop do
        frmsize = LibV4L2::V4l2FrmSizeEnum.new
        frmsize.index = index
        frmsize.pixel_format = pixelformat

        raise DeviceError.new("Device not open") unless @fd
        result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_ENUM_FRAMESIZES, pointerof(frmsize))
        break if result < 0

        if frmsize.type == LibV4L2::V4L2_FRMSIZE_TYPE_DISCRETE
          resolutions << {width: frmsize.discrete.width, height: frmsize.discrete.height}
        elsif frmsize.type == LibV4L2::V4L2_FRMSIZE_TYPE_STEPWISE
          resolutions << {width: frmsize.stepwise.max_width, height: frmsize.stepwise.max_height}
        end

        index += 1
      end

      resolutions
    end

    # Returns an array of discrete framerates (as {numerator, denominator}), or a single stepwise/continuous range (as a NamedTuple)
    def supported_framerates(pixelformat : UInt32, width : UInt32, height : UInt32)
      ensure_open

      framerates = [] of NamedTuple(numerator: UInt32, denominator: UInt32)
      stepwise_info = nil
      index = 0_u32
      frmival_type = nil

      loop do
        frmival = LibV4L2::V4l2FrmIvalEnum.new
        frmival.index = index
        frmival.pixel_format = pixelformat
        frmival.width = width
        frmival.height = height

        raise DeviceError.new("Device not open") unless @fd
        result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_ENUM_FRAMEINTERVALS, pointerof(frmival))
        break if result < 0

        frmival_type ||= frmival.type

        if frmival.type == LibV4L2::V4L2_FRMIVAL_TYPE_DISCRETE
          framerates << {numerator: frmival.data.discrete.numerator, denominator: frmival.data.discrete.denominator}
        elsif frmival.type == LibV4L2::V4L2_FRMIVAL_TYPE_STEPWISE || frmival.type == LibV4L2::V4L2_FRMIVAL_TYPE_CONTINUOUS
          # Only need to get this once
          stepwise_info ||= {
            min:  {numerator: frmival.data.stepwise.min.numerator, denominator: frmival.data.stepwise.min.denominator},
            max:  {numerator: frmival.data.stepwise.max.numerator, denominator: frmival.data.stepwise.max.denominator},
            step: {numerator: frmival.data.stepwise.step.numerator, denominator: frmival.data.stepwise.step.denominator},
            type: frmival.type,
          }
          break
        end

        index += 1
      end

      if frmival_type == LibV4L2::V4L2_FRMIVAL_TYPE_DISCRETE
        framerates
      elsif stepwise_info
        stepwise_info
      else
        [] of NamedTuple(numerator: UInt32, denominator: UInt32)
      end
    end

    # Get current format
    def format : Format
      ensure_open

      v4l2_format = LibV4L2::V4l2Format.new
      v4l2_format.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_G_FMT, pointerof(v4l2_format))
      raise DeviceError.new("Failed to get format") if result < 0

      # Cast the format data to pix format
      pix = v4l2_format.fmt_data.to_unsafe.as(LibV4L2::V4l2PixFormat*)
      format = Format.new(0_u32, "Current Format", pix.value.pixelformat, 0_u32,
        pix.value.width, pix.value.height, pix.value.bytesperline, pix.value.sizeimage)

      @current_format = format
      format
    end

    # Set format
    def set_format(width : UInt32, height : UInt32, pixelformat : UInt32) : Format
      ensure_open

      v4l2_format = LibV4L2::V4l2Format.new
      v4l2_format.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE

      # Cast the format data to pix format and set values
      pix = v4l2_format.fmt_data.to_unsafe.as(LibV4L2::V4l2PixFormat*)
      pix.value.width = width
      pix.value.height = height
      pix.value.pixelformat = pixelformat
      pix.value.field = LibV4L2::V4L2_FIELD_INTERLACED

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_S_FMT, pointerof(v4l2_format))
      puts "[DEBUG] ioctl VIDIOC_S_FMT result: #{result}"
      if result < 0
        puts "[DEBUG] errno: #{Errno.value} (\#{String.new(LibC.strerror(Errno.value))})"
        raise DeviceError.new("Failed to set format: \#{String.new(LibC.strerror(perror))}")
      end

      # Get the actual format set by the driver
      format
    end

    # Set JPEG compression quality
    def jpeg_quality=(quality : Int32)
      ensure_open

      control = LibV4L2::V4l2Control.new
      control.id = LibV4L2::V4L2_CID_JPEG_COMPRESSION_QUALITY
      control.value = quality

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_S_CTRL, pointerof(control))
      raise DeviceError.new("Failed to set JPEG quality") if result < 0
    end

    # Set framerate
    def framerate=(fps : UInt32)
      ensure_open

      parm = LibV4L2::V4l2Streamparm.new
      parm.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE

      # Get current parameters first to avoid overwriting other settings
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_G_PARM, pointerof(parm))
      raise DeviceError.new("Failed to get stream parameters") if result < 0

      parm.parm.capture.timeperframe.numerator = 1
      parm.parm.capture.timeperframe.denominator = fps

      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_S_PARM, pointerof(parm))
      raise DeviceError.new("Failed to set framerate") if result < 0
    end

    # Request buffers for streaming
    def request_buffers(count : UInt32, memory_type : UInt32 = LibV4L2::V4L2_MEMORY_MMAP) : BufferManager
      ensure_open

      req_bufs = LibV4L2::V4l2RequestBuffers.new
      req_bufs.count = count
      req_bufs.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      req_bufs.memory = memory_type

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_REQBUFS, pointerof(req_bufs))
      raise DeviceError.new("Failed to request buffers") if result < 0

      @buffer_manager = BufferManager.new(req_bufs.count, LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE, memory_type)

      # Set up individual buffers
      req_bufs.count.times do |i|
        buffer = query_buffer(i.to_u32)

        if memory_type == LibV4L2::V4L2_MEMORY_MMAP
          if @fd && buffer.offset
            offset = buffer.offset
            ptr = LibC.mmap(nil, buffer.length, LibV4L2::PROT_READ | LibV4L2::PROT_WRITE,
              LibV4L2::MAP_SHARED, @fd.as(Int32), offset ? offset.to_i64 : 0_i64)
            raise DeviceError.new("Failed to mmap buffer") if ptr == LibV4L2::MAP_FAILED
            buffer.set_mmap_info(offset || 0_u32, ptr)
          else
            raise DeviceError.new("Invalid buffer offset or device fd for mmap")
          end
        end

        @buffer_manager.add_buffer(buffer)
      end

      @buffer_manager
    end

    # Query a specific buffer
    private def query_buffer(index : UInt32) : Buffer
      ensure_open

      v4l2_buf = LibV4L2::V4l2Buffer.new
      v4l2_buf.index = index
      v4l2_buf.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      v4l2_buf.memory = LibV4L2::V4L2_MEMORY_MMAP

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_QUERYBUF, pointerof(v4l2_buf))
      raise DeviceError.new("Failed to query buffer") if result < 0

      timestamp = Time.unix(v4l2_buf.timestamp.tv_sec) + Time::Span.new(nanoseconds: v4l2_buf.timestamp.tv_usec * 1000)
      buffer = Buffer.new(v4l2_buf.index, v4l2_buf.length, v4l2_buf.bytesused,
        v4l2_buf.flags, v4l2_buf.sequence, timestamp)

      # Store offset for later mmap
      buffer.set_mmap_info(v4l2_buf.m.offset, Pointer(Void).null)

      buffer
    end

    # Queue a buffer for capture
    def queue_buffer(buffer : Buffer)
      ensure_open

      v4l2_buf = LibV4L2::V4l2Buffer.new
      v4l2_buf.index = buffer.index
      v4l2_buf.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      v4l2_buf.memory = LibV4L2::V4L2_MEMORY_MMAP

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_QBUF, pointerof(v4l2_buf))
      raise DeviceError.new("Failed to queue buffer") if result < 0
    end

    # Dequeue a buffer (get captured data)
    def dequeue_buffer : Buffer
      ensure_open

      v4l2_buf = LibV4L2::V4l2Buffer.new
      v4l2_buf.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      v4l2_buf.memory = LibV4L2::V4L2_MEMORY_MMAP

      # Try to dequeue with retries for non-blocking mode
      retries = 0
      max_retries = 100 # ~1 second timeout with 10ms sleep

      loop do
        raise DeviceError.new("Device not open") unless @fd
        result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_DQBUF, pointerof(v4l2_buf))
        if result >= 0
          break
        end

        retries += 1
        if retries > max_retries
          raise DeviceError.new("Failed to dequeue buffer (timeout)")
        end

        # Sleep for a short time before retrying
        sleep(Time::Span.new(nanoseconds: 10_000_000)) # 10ms
      end

      # Find the buffer in our manager
      original_buffer = @buffer_manager[v4l2_buf.index]

      # Update buffer information
      timestamp = Time.unix(v4l2_buf.timestamp.tv_sec) + Time::Span.new(nanoseconds: v4l2_buf.timestamp.tv_usec * 1000)
      Buffer.new(v4l2_buf.index, v4l2_buf.length, v4l2_buf.bytesused,
        v4l2_buf.flags, v4l2_buf.sequence, timestamp).tap do |updated_buffer|
        if original_buffer.mmap_ptr != Pointer(Void).null && original_buffer.offset
          updated_buffer.set_mmap_info(original_buffer.offset.as(UInt32), original_buffer.mmap_ptr)
        end
      end
    end

    # Start streaming
    def start_streaming
      ensure_open

      buf_type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_STREAMON, pointerof(buf_type))
      raise DeviceError.new("Failed to start streaming") if result < 0
    end

    # Stop streaming
    def stop_streaming
      ensure_open

      buf_type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_STREAMOFF, pointerof(buf_type))
      raise DeviceError.new("Failed to stop streaming") if result < 0
    end

    # Capture a single frame (convenience method)
    def capture_frame : Buffer
      ensure_open

      unless @buffer_manager
        request_buffers(4)
      end

      # Queue all buffers
      if @buffer_manager
        @buffer_manager.each do |buffer|
          queue_buffer(buffer)
        end
      end

      # Start streaming
      start_streaming

      begin
        # Wait for a frame
        buffer = dequeue_buffer

        # Re-queue the buffer for next capture
        queue_buffer(buffer)

        buffer
      ensure
        stop_streaming
      end
    end

    # Get inputs available on the device
    def inputs : Array(String)
      ensure_open

      inputs = [] of String
      index = 0_u32

      loop do
        input = LibV4L2::V4l2Input.new
        input.index = index

        raise DeviceError.new("Device not open") unless @fd
        result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_ENUMINPUT, pointerof(input))
        break if result < 0

        inputs << String.new(input.name.to_unsafe)
        index += 1
      end

      inputs
    end

    # Get current input
    def current_input : Int32
      ensure_open

      input = 0
      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_G_INPUT, pointerof(input))
      raise DeviceError.new("Failed to get current input") if result < 0

      input
    end

    # Set input
    def input=(index : Int32)
      ensure_open

      raise DeviceError.new("Device not open") unless @fd
      result = LibV4L2.ioctl(@fd.as(Int32), LibV4L2::VIDIOC_S_INPUT, pointerof(index))
      raise DeviceError.new("Failed to set input") if result < 0
    end

    # Check if device is open
    def open?
      !@fd.nil?
    end

    def to_s(io)
      io << "Device(path: #{@device_path}, open: #{open?}"
      if @capability
        io << ", card: #{@capability.card}"
      end
      io << ")"
    end

    def finalize
      close
    end
  end
end
