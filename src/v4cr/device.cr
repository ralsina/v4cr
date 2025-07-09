module V4cr
  # Main class for interacting with V4L2 devices
  class Device
    getter device_path : String
    getter fd : Int32?
    getter capability : Capability?
    getter current_format : Format?
    getter buffer_manager : BufferManager?

    def initialize(@device_path : String)
      @fd = nil
      @capability = nil
      @current_format = nil
      @buffer_manager = nil
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
        if @buffer_manager
          @buffer_manager.not_nil!.each do |buffer|
            if ptr = buffer.mmap_ptr
              LibC.munmap(ptr, buffer.length)
            end
          end
          @buffer_manager = nil
        end

        LibC.close(@fd.not_nil!)
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
      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_QUERYCAP, pointerof(cap))
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

        result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_ENUM_FMT, pointerof(fmt_desc))
        break if result < 0

        description = String.new(fmt_desc.description.to_unsafe)
        format = Format.new(fmt_desc.index, description, fmt_desc.pixelformat, fmt_desc.flags)
        formats << format

        index += 1
      end

      formats
    end

    # Get current format
    def get_format : Format
      ensure_open

      v4l2_format = LibV4L2::V4l2Format.new
      v4l2_format.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_G_FMT, pointerof(v4l2_format))
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

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_S_FMT, pointerof(v4l2_format))
      raise DeviceError.new("Failed to set format") if result < 0

      # Get the actual format set by the driver
      get_format
    end

    # Request buffers for streaming
    def request_buffers(count : UInt32, memory_type : UInt32 = LibV4L2::V4L2_MEMORY_MMAP) : BufferManager
      ensure_open

      req_bufs = LibV4L2::V4l2RequestBuffers.new
      req_bufs.count = count
      req_bufs.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      req_bufs.memory = memory_type

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_REQBUFS, pointerof(req_bufs))
      raise DeviceError.new("Failed to request buffers") if result < 0

      @buffer_manager = BufferManager.new(req_bufs.count, LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE, memory_type)

      # Set up individual buffers
      req_bufs.count.times do |i|
        buffer = query_buffer(i.to_u32)
        
        if memory_type == LibV4L2::V4L2_MEMORY_MMAP
          # Map the buffer
          ptr = LibC.mmap(nil, buffer.length, LibV4L2::PROT_READ | LibV4L2::PROT_WRITE,
                            LibV4L2::MAP_SHARED, @fd.not_nil!, buffer.offset.not_nil!)
          raise DeviceError.new("Failed to mmap buffer") if ptr == LibV4L2::MAP_FAILED
          
          buffer.set_mmap_info(buffer.offset.not_nil!, ptr)
        end

        @buffer_manager.not_nil!.add_buffer(buffer)
      end

      @buffer_manager.not_nil!
    end

    # Query a specific buffer
    private def query_buffer(index : UInt32) : Buffer
      ensure_open

      v4l2_buf = LibV4L2::V4l2Buffer.new
      v4l2_buf.index = index
      v4l2_buf.type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      v4l2_buf.memory = LibV4L2::V4L2_MEMORY_MMAP

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_QUERYBUF, pointerof(v4l2_buf))
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

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_QBUF, pointerof(v4l2_buf))
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
      max_retries = 100  # ~1 second timeout with 10ms sleep
      
      loop do
        result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_DQBUF, pointerof(v4l2_buf))
        if result >= 0
          break
        end
        
        retries += 1
        if retries > max_retries
          raise DeviceError.new("Failed to dequeue buffer (timeout)")
        end
        
        # Sleep for a short time before retrying
        sleep(Time::Span.new(nanoseconds: 10_000_000))  # 10ms
      end

      # Find the buffer in our manager
      original_buffer = @buffer_manager.not_nil![v4l2_buf.index]
      
      # Update buffer information
      timestamp = Time.unix(v4l2_buf.timestamp.tv_sec) + Time::Span.new(nanoseconds: v4l2_buf.timestamp.tv_usec * 1000)
      Buffer.new(v4l2_buf.index, v4l2_buf.length, v4l2_buf.bytesused,
                v4l2_buf.flags, v4l2_buf.sequence, timestamp).tap do |updated_buffer|
        if original_buffer.mmap_ptr && original_buffer.mmap_ptr != Pointer(Void).null
          updated_buffer.set_mmap_info(original_buffer.offset.not_nil!, original_buffer.mmap_ptr.not_nil!)
        end
      end
    end

    # Start streaming
    def start_streaming
      ensure_open

      buf_type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_STREAMON, pointerof(buf_type))
      raise DeviceError.new("Failed to start streaming") if result < 0
    end

    # Stop streaming
    def stop_streaming
      ensure_open

      buf_type = LibV4L2::V4L2_BUF_TYPE_VIDEO_CAPTURE
      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_STREAMOFF, pointerof(buf_type))
      raise DeviceError.new("Failed to stop streaming") if result < 0
    end

    # Capture a single frame (convenience method)
    def capture_frame : Buffer
      ensure_open

      unless @buffer_manager
        request_buffers(4)
      end

      # Queue all buffers
      @buffer_manager.not_nil!.each do |buffer|
        queue_buffer(buffer)
      end

      # Start streaming
      start_streaming

      begin
        # Wait for a frame
        buffer = dequeue_buffer
        
        # Re-queue the buffer for next capture
        queue_buffer(buffer)
        
        return buffer
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

        result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_ENUMINPUT, pointerof(input))
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
      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_G_INPUT, pointerof(input))
      raise DeviceError.new("Failed to get current input") if result < 0

      input
    end

    # Set input
    def set_input(index : Int32)
      ensure_open

      result = LibV4L2.ioctl(@fd.not_nil!, LibV4L2::VIDIOC_S_INPUT, pointerof(index))
      raise DeviceError.new("Failed to set input") if result < 0
    end

    # Check if device is open
    def open?
      !@fd.nil?
    end

    def to_s(io)
      io << "Device(path: #{@device_path}, open: #{open?}"
      if @capability
        io << ", card: #{@capability.not_nil!.card}"
      end
      io << ")"
    end

    def finalize
      close
    end
  end
end
