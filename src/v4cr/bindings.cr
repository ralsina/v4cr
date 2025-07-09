require "lib_c"

module V4cr
  # Low-level bindings to the v4l2 C API
  @[Link("c")]
  lib LibV4L2
    # v4l2 constants
    VIDIOC_QUERYCAP     = 0x80685600_u32
    VIDIOC_ENUM_FMT     = 0xc0405602_u32
    VIDIOC_G_FMT        = 0xc0d05604_u32
    VIDIOC_S_FMT        = 0xc0d05605_u32
    VIDIOC_REQBUFS      = 0xc0145608_u32
    VIDIOC_QUERYBUF     = 0xc0585609_u32
    VIDIOC_QBUF         = 0xc058560f_u32
    VIDIOC_DQBUF        = 0xc0585611_u32
    VIDIOC_STREAMON     = 0x40045612_u32
    VIDIOC_STREAMOFF    = 0x40045613_u32
    VIDIOC_G_PARM       = 0xc0cc5615_u32
    VIDIOC_S_PARM       = 0xc0cc5616_u32
    VIDIOC_G_CTRL       = 0xc008561b_u32
    VIDIOC_S_CTRL       = 0xc008561c_u32
    VIDIOC_QUERYCTRL    = 0xc0445624_u32
    VIDIOC_G_INPUT      = 0x80045626_u32
    VIDIOC_S_INPUT      = 0xc0045627_u32
    VIDIOC_ENUMINPUT    = 0xc050561a_u32

    # Capability flags
    V4L2_CAP_VIDEO_CAPTURE      = 0x00000001_u32
    V4L2_CAP_VIDEO_OUTPUT       = 0x00000002_u32
    V4L2_CAP_VIDEO_OVERLAY      = 0x00000004_u32
    V4L2_CAP_STREAMING          = 0x04000000_u32
    V4L2_CAP_READWRITE          = 0x01000000_u32

    # Buffer types
    V4L2_BUF_TYPE_VIDEO_CAPTURE = 1_u32
    V4L2_BUF_TYPE_VIDEO_OUTPUT  = 2_u32

    # Memory types
    V4L2_MEMORY_MMAP    = 1_u32
    V4L2_MEMORY_USERPTR = 2_u32
    V4L2_MEMORY_OVERLAY = 3_u32

    # Field types
    V4L2_FIELD_ANY      = 0_u32
    V4L2_FIELD_NONE     = 1_u32
    V4L2_FIELD_TOP      = 2_u32
    V4L2_FIELD_BOTTOM   = 3_u32
    V4L2_FIELD_INTERLACED = 4_u32

    # Pixel formats (common ones)
    V4L2_PIX_FMT_RGB332  = 0x31424752_u32
    V4L2_PIX_FMT_RGB565  = 0x36424752_u32
    V4L2_PIX_FMT_RGB24   = 0x33424752_u32
    V4L2_PIX_FMT_RGB32   = 0x34424752_u32
    V4L2_PIX_FMT_YUYV    = 0x56595559_u32
    V4L2_PIX_FMT_UYVY    = 0x59565955_u32
    V4L2_PIX_FMT_YUV420  = 0x32315559_u32
    V4L2_PIX_FMT_YUV422P = 0x50323234_u32
    V4L2_PIX_FMT_MJPEG   = 0x4745504D_u32
    V4L2_PIX_FMT_JPEG    = 0x4745504A_u32

    # Buffer flags
    V4L2_BUF_FLAG_MAPPED    = 0x00000001_u32
    V4L2_BUF_FLAG_QUEUED    = 0x00000002_u32
    V4L2_BUF_FLAG_DONE      = 0x00000004_u32
    V4L2_BUF_FLAG_ERROR     = 0x00000040_u32

    # Structures
    struct V4l2Capability
      driver : UInt8[16]
      card : UInt8[32]
      bus_info : UInt8[32]
      version : UInt32
      capabilities : UInt32
      device_caps : UInt32
      reserved : UInt32[3]
    end

    struct V4l2PixFormat
      width : UInt32
      height : UInt32
      pixelformat : UInt32
      field : UInt32
      bytesperline : UInt32
      sizeimage : UInt32
      colorspace : UInt32
      priv : UInt32
      flags : UInt32
      ycbcr_enc : UInt32  # This is actually a union, but we can treat as UInt32
      quantization : UInt32
      xfer_func : UInt32
    end

    struct V4l2Format
      type : UInt32
      padding1 : UInt32  # 4 bytes of padding between type and fmt union
      fmt_data : UInt8[200]
      # Add padding to match C structure size (208 - 4 - 4 - 200 = 0)
    end

    struct V4l2FmtDesc
      index : UInt32
      type : UInt32
      flags : UInt32
      description : UInt8[32]
      pixelformat : UInt32
      reserved : UInt32[4]
    end

    struct V4l2Timecode
      type : UInt32
      flags : UInt32
      frames : UInt8
      seconds : UInt8
      minutes : UInt8
      hours : UInt8
      userbits : UInt8[4]
    end

    struct V4l2RequestBuffers
      count : UInt32
      type : UInt32
      memory : UInt32
      reserved : UInt32[2]
    end

    struct V4l2Buffer
      index : UInt32
      type : UInt32
      bytesused : UInt32
      flags : UInt32
      field : UInt32
      timestamp : LibC::Timeval
      timecode : V4l2Timecode
      sequence : UInt32
      memory : UInt32
      m : BufferUnion
      length : UInt32
      reserved2 : UInt32
      reserved : UInt32
    end

    union BufferUnion
      offset : UInt32
      userptr : UInt64
      fd : Int32
    end

    struct V4l2Input
      index : UInt32
      name : UInt8[32]
      type : UInt32
      audioset : UInt32
      tuner : UInt32
      std : UInt64
      status : UInt32
      capabilities : UInt32
      reserved : UInt32[3]
    end

    # We'll use LibC functions directly in the code
    # Define ioctl function since it's not directly available in LibC
    fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int

    # Memory mapping constants
    PROT_READ  = 0x1
    PROT_WRITE = 0x2
    MAP_SHARED = 0x01
    MAP_FAILED = Pointer(Void).new(0xFFFFFFFF_u64)

    # File control constants
    O_RDWR    = 0x0002
    O_NONBLOCK = 0x0800
  end
end
