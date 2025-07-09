# V4cr - A Crystal wrapper for Video4Linux2 (v4l2) API
#
# This library provides a high-level interface to interact with video capture
# devices on Linux systems using the v4l2 API.
#
# Basic usage:
# ```
# require "v4cr"
#
# device = V4cr::Device.new("/dev/video0")
# device.open
# formats = device.supported_formats
# device.close
# ```
module V4cr
  VERSION = "0.1.0"

  # Base exception class for all V4cr errors
  class Error < Exception
  end

  # Raised when a device operation fails
  class DeviceError < Error
  end

  # Raised when a format is not supported
  class FormatError < Error
  end

  # Raised when an I/O operation fails
  class IOError < Error
  end
end

require "./v4cr/bindings"
require "./v4cr/format"
require "./v4cr/capability"
require "./v4cr/buffer"
require "./v4cr/device"
