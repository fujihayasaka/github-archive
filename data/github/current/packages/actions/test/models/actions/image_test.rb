# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::ImageTest < GitHub::TestCase
  def setup
    @linux_x64_image = Actions::Image.new(
      id: "1",
      display_name: "Ubuntu 20.04",
      os_type: "Linux",
      architecture: "X64",
      size_gb: 10,
      source: :Curated,
    )
    @linux_arm64_image = Actions::Image.new(
      id: "1",
      display_name: "Ubuntu 20.04",
      os_type: "Linux",
      architecture: "Arm64",
      size_gb: 10,
      source: :Curated,
    )
    @windows_x64_image = Actions::Image.new(
      id: "2",
      display_name: "Windows Server 2019",
      os_type: "Windows",
      architecture: "X64",
      size_gb: 20,
      source: :Curated,
    )
    @windows_arm64_image = Actions::Image.new(
      id: "2",
      display_name: "Windows Server 2019",
      os_type: "Windows",
      architecture: "Arm64",
      source: :Curated,
    )
  end

  test "platform method returns correct platform string" do
    assert_equal "linux-x64", @linux_x64_image.platform
    assert_equal "linux-arm64", @linux_arm64_image.platform
    assert_equal "win-x64", @windows_x64_image.platform
    assert_equal "win-arm64", @windows_arm64_image.platform
  end

  test "platform_to_ostype method returns correct OS type" do
    assert_equal "Windows", Actions::Image.platform_to_ostype("win-x64")
    assert_equal "Linux", Actions::Image.platform_to_ostype("linux-x64")
  end

  test "platform_to_architecture method returns correct architecture" do
    assert_equal "Arm64", Actions::Image.platform_to_architecture("linux-arm64")
    assert_equal "X64", Actions::Image.platform_to_architecture("linux-x64")
  end
end
