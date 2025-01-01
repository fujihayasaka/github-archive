# typed: true
# frozen_string_literal: true

require "test_helper"

module PackageRegistry
  class PackageMetadataTest < GitHub::TestCase
    setup do
      @package = stub(ecosystem: :container)
      @version = stub
      @latest_version = stub
      @subject = PackageMetadata.new(stub(package: @package, versions: [@version], latest_version: @latest_version, total_version_count: 100))
    end

    test "#package" do
      assert @subject.package.is_a?(PackageRegistry::Package)
    end

    test "#package_versions" do
      assert_equal 1, @subject.package_versions.length
      assert @subject.package_versions.all? { |v| v.is_a?(PackageRegistry::PackageVersion) }
    end

    test "#latest_version" do
      assert @subject.latest_version.is_a?(PackageRegistry::PackageVersion)
    end

    test "#total_version_count" do
      assert @subject.total_version_count.instance_of?(Integer)
    end
  end
end
