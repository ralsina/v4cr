require "./spec_helper"

describe V4cr do
  describe "VERSION" do
    it "has a version" do
      V4cr::VERSION.should eq("0.1.0")
    end
  end

  describe "Device" do
    it "can create a device instance" do
      device = V4cr::Device.new("/dev/video0")
      device.device_path.should eq("/dev/video0")
      device.open?.should be_false
    end

    it "can be closed multiple times safely" do
      device = V4cr::Device.new("/dev/video0")
      device.close  # Should not raise
      device.close  # Should not raise
    end
  end

  describe "Error classes" do
    it "has proper error hierarchy" do
      V4cr::DeviceError.new("test").should be_a(V4cr::Error)
      V4cr::FormatError.new("test").should be_a(V4cr::Error)
      V4cr::IOError.new("test").should be_a(V4cr::Error)
    end
  end
end
