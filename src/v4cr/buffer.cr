module V4cr
  # Represents a memory buffer for video data
  class Buffer
    getter index : UInt32
    getter length : UInt32
    getter bytesused : UInt32
    getter flags : UInt32
    getter sequence : UInt32
    getter timestamp : Time
    getter data : Bytes?

    # For mmap buffers
    getter offset : UInt32?
    getter mmap_ptr : Void*?

    # For userptr buffers
    getter userptr : UInt64?

    def initialize(@index : UInt32, @length : UInt32, @bytesused : UInt32, 
                   @flags : UInt32, @sequence : UInt32, @timestamp : Time)
      @data = nil
      @offset = nil
      @mmap_ptr = nil
      @userptr = nil
    end

    # Set mmap buffer information
    def set_mmap_info(offset : UInt32, mmap_ptr : Void*)
      @offset = offset
      @mmap_ptr = mmap_ptr
      # Only create Bytes if we have a valid pointer
      if mmap_ptr != Pointer(Void).null
        @data = Bytes.new(mmap_ptr.as(UInt8*), @length)
      end
    end

    # Set userptr buffer information
    def set_userptr_info(@userptr : UInt64)
      @data = Bytes.new(Pointer(UInt8).new(@userptr), @length)
    end

    # Check if buffer is mapped
    def mapped?
      (@flags & LibV4L2::V4L2_BUF_FLAG_MAPPED) != 0
    end

    # Check if buffer is queued
    def queued?
      (@flags & LibV4L2::V4L2_BUF_FLAG_QUEUED) != 0
    end

    # Check if buffer is done (ready for dequeuing)
    def done?
      (@flags & LibV4L2::V4L2_BUF_FLAG_DONE) != 0
    end

    # Check if buffer has an error
    def error?
      (@flags & LibV4L2::V4L2_BUF_FLAG_ERROR) != 0
    end

    # Get the actual data from the buffer
    def data
      raise IOError.new("Buffer not mapped") unless @data
      # Ensure we don't access beyond buffer boundaries
      bytes_to_read = [@bytesused, @length].min
      @data.not_nil![0, bytes_to_read]
    end

    # Get the full buffer (including unused space)
    def full_buffer
      raise IOError.new("Buffer not mapped") unless @data
      @data.not_nil!
    end

    def to_s(io)
      io << "Buffer(index: #{@index}, length: #{@length}, "
      io << "bytesused: #{@bytesused}, sequence: #{@sequence}, "
      io << "mapped: #{mapped?}, queued: #{queued?}, done: #{done?}, "
      io << "error: #{error?})"
    end
  end

  # Manages a collection of buffers for streaming
  class BufferManager
    getter buffers : Array(Buffer)
    getter buffer_count : UInt32
    getter buffer_type : UInt32
    getter memory_type : UInt32

    def initialize(@buffer_count : UInt32, @buffer_type : UInt32, @memory_type : UInt32)
      @buffers = [] of Buffer
    end

    def add_buffer(buffer : Buffer)
      @buffers << buffer
    end

    def [](index : Int)
      @buffers[index]
    end

    def size
      @buffers.size
    end

    def each
      @buffers.each { |buffer| yield buffer }
    end

    def each_with_index
      @buffers.each_with_index { |buffer, index| yield buffer, index }
    end

    def to_s(io)
      io << "BufferManager(count: #{@buffer_count}, type: #{@buffer_type}, "
      io << "memory: #{@memory_type}, buffers: #{@buffers.size})"
    end
  end
end
