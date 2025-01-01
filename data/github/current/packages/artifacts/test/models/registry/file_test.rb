# typed: true
# frozen_string_literal: true

require "test_helper"

class RegistryFileTest < GitHub::TestCase
  include GitHub::RegistryPackageHelper
  include UploadableTestHelpers
  include CdnTestHelper

  fixtures do
    @user1 = create :user, login: "scottjg", password: GitHub.default_password
    @repo = create :repository, owner: @user1, from_example: :repository_test_simple

    @repo2 = create :repository, owner: @user1, from_example: :repository_test_simple

    @user2 = create :user, login: "skalnik", password: GitHub.default_password
    @repo3 = create(:public_repository, owner: @user2, from_example: :repository_test_simple)

    @package = Registry::Package.new(
      name: "irrelevant-package",
      repository: @repo,
      owner: @repo.owner,
      package_type: :npm,
    )

    @version = make_registry_package_version(registry_package: @package, tag_name: "0.0.1")
    @version2 = make_registry_package_version(registry_package: @package, tag_name: "0.0.2")
    @package.package_versions << @version
    @package.package_versions << @version2
    @package.save
  end

  test "Duplicates package version <-> package file mapping" do
    v3 = make_registry_package_version(registry_package: @package, tag_name: "0.0.3")
    v3.save!
    p1 = Registry::File.new(
      filename: "1",
      registry_package_name: "p1",
      registry_package_type: :npm,
      version: v3.version,
      package_version_id: v3.id,
      size: 1,
    )
    p1.save!

    p1.package_version = v3
    p1.save!

    assert_manifest_entry_exists(v3, p1)
  end

  test "fails to create a file with md5 hash in fips mode" do
    GitHub.stubs(:fips_mode?).returns(true)
    p1 = Registry::File.new(
      filename: "2",
      registry_package_name: "p1",
      registry_package_type: :npm,
      version: @version.version,
      package_version_id: @version.id,
      size: 1,
      md5: "MD5",
    )
    p1.package_version = @version
    refute p1.save
    assert p1.errors.include?(:md5)
  end

  test "creates a file without md5 hash in fips mode" do
    GitHub.stubs(:fips_mode?).returns(true)
    p1 = Registry::File.new(
      filename: "2",
      registry_package_name: "p1",
      registry_package_type: :npm,
      version: @version.version,
      package_version_id: @version.id,
      size: 1,
      md5: "",
    )
    p1.package_version = @version
    assert p1.save
    refute p1.errors.include?(:md5)
  end

  test "Can add package file to multiple versions" do
    r1 = create(:release,
        repository: @repo,
        tag_name: "0.0.4",
        author: @repo.owner,
      )
    r1.save!

    p1 = Registry::File.new(
      filename: "2",
      registry_package_name: "p1",
      registry_package_type: :npm,
      version: @version.version,
      package_version_id: @version.id,
      size: 1,
    )
    p1.package_version = @version
    p1.save!

    p1.package_version = @version2
    p1.save!
    assert_manifest_entry_exists(@version, p1)
    assert_manifest_entry_exists(@version2, p1)
  end

  test "Can add multiple package files to multiple versions" do
    r1 = create(:release,
        repository: @repo,
        tag_name: "0.0.4",
        author: @repo.owner,
      )
    r1.save!

    p1 = Registry::File.new(
      filename: "3",
      registry_package_name: "p1",
      registry_package_type: :npm,
      version: @version.version,
      package_version_id: @version.id,
      size: 1,
    )

    p2 = Registry::File.new(
      filename: "4",
      registry_package_name: "p2",
      registry_package_type: :npm,
      version: @version.version,
      package_version_id: @version2.id,
      size: 1,
    )

    p1.package_version = @version
    p1.save!

    p2.package_version = @version
    p2.save!

    p1.package_version = @version2
    p1.save!

    p2.package_version = @version2
    p2.save!

    assert_manifest_entry_exists(@version, p1)
    assert_manifest_entry_exists(@version2, p1)

    assert_manifest_entry_exists(@version, p2)
    assert_manifest_entry_exists(@version2, p2)
  end

  def assert_manifest_entry_exists(package_version, package_file)
    assert Registry::ManifestEntry.exists?(package_version_id: package_version.id, package_file_id: package_file.id), "Expected join entry to exist"
    assert package_file.package_versions.exists?(id: package_version.id), "Expected package_file to have package_version"
    assert package_version.package_files.exists?(id: package_file.id), "Expected package_version to have package_file"
  end

  context "storage policy", skip_enterprise: true do
    test "uses fastly accelerated url" do
      v3 = make_registry_package_version(registry_package: @package, tag_name: "0.0.3")
      v3.save!
      p1 = Registry::File.new(
        filename: "1",
        registry_package_name: "p1",
        registry_package_type: :npm,
        version: v3.version,
        package_version_id: v3.id,
        size: 1,
      )
      p1.save!

      url = p1.url
      assert_match /^https:\/\/#{p1.storage_fastly_acceleration_bucket(@repo)}\/.+/, url
    end
  end
end
