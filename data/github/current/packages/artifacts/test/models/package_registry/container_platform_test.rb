# typed: true
# frozen_string_literal: true

require "test_helper"

class PackageRegistry::ContainerPlatformTest < GitHub::TestCase
  context ".to_proc" do
    test "returns ContainerPlatform instance" do
      container_platform = PackageRegistry::ContainerPlatform.to_proc.call(
        "os" => "linux",
        "architecture" => "arm",
        "digest" => "digest"
      )

      assert_equal "linux", container_platform.os
      assert_equal "arm", container_platform.architecture
      assert_equal "digest", container_platform.digest
    end
  end

  context "#descriptor" do
    test "returns descriptor with os/architecture" do
      container_platform = PackageRegistry::ContainerPlatform.to_proc.call(
        "os" => "linux",
        "architecture" => "arm",
        "digest" => "digest"
      )

      assert_equal "linux/arm", container_platform.descriptor
    end

    test "returns descriptor with os/version/architecture" do
      container_platform = PackageRegistry::ContainerPlatform.to_proc.call(
        "os" => "linux",
        "os.version" => "ubuntu",
        "architecture" => "arm",
        "digest" => "digest"
      )

      assert_equal "linux/ubuntu/arm", container_platform.descriptor
    end

    test "returns descriptor with os/architecture/variant" do
      container_platform = PackageRegistry::ContainerPlatform.to_proc.call(
        "os" => "linux",
        "architecture" => "arm",
        "variant" => "v7",
        "digest" => "digest"
      )

      assert_equal "linux/arm/v7", container_platform.descriptor
    end
  end
end
