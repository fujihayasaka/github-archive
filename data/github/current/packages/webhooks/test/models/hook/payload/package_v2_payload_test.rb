# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/registry_metadata/v0/entities/package_pb"
require "hydro/schemas/registry_metadata/v0/entities/version_pb"
require "hydro/schemas/registry_metadata/v0/entities/ecosystem_pb"
require "hydro/schemas/registry_metadata/v0/entities/container_version_metadata_pb"
require "hydro/schemas/registry_metadata/v0/entities/container_tag_pb"
require "hydro/schemas/registry_metadata/v0/entities/container_labels_pb"
require "hydro/schemas/registry_metadata/v0/entities/container_manifest_pb"

class HookPayloadPackageV2PayloadTest < GitHub::TestCase
  #include GitHub::RegistryPackageHelper
  include Hydro::Schemas::RegistryMetadata::V0::Entities

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org = create(:organization, admin: @org_admin, plan: "diamond")
    @org.save!
    @team = create(:team, organization: @org, permission: "admin")
    @team.add_member @org_admin
    @owner = create(:user, login: "jessicard", password: GitHub.default_password, plan: "large")

    @contributor = create(:user, login: "scottjg", password: GitHub.default_password, plan: "large")

    @user_no_access = create(:user, login: "phanatic", password: GitHub.default_password, plan: "large")

    @team.add_member @owner
    @team.add_member @contributor
    @team.add_member @user_no_access

    @repo1 = create(:private_repository, owner: @owner, name: "test-symlink-docker-image", description: "a repository", from_example: :repository_test_symlink)
    @team.add_repository @repo1, :pull

    example_repo_snapshot
    @repo1.save!

    @registry_package = Package.new({ id: 123,
                                     namespace: @org.name,
                                     name: "test-docker-image",
                                     ecosystem: Ecosystem::CONTAINER,
                                     created_at: Google::Protobuf::Timestamp.new,
                                     updated_at: Google::Protobuf::Timestamp.new })

    @registry_package1 = Package.new({ id: 1234,
                                     namespace: @org.name,
                                     name: "test-docker-image",
                                     ecosystem: Ecosystem::CONTAINER,
                                     created_at: Google::Protobuf::Timestamp.new,
                                     updated_at: Google::Protobuf::Timestamp.new,
                                     repo_id: @repo1.id })

    @version_metadata = ContainerVersionMetadata.new({ tag: ContainerTag.new({ name: "asdf", digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c47272962dd60f71fc9" }),
                                                      manifest: ContainerManifest.new({ uri: "http://github.com", digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c4727296asdf0f71fc9" }),
                                                      labels: ContainerLabels.new({ description: "test data" })
                                                     })

    @package_version = Version.new({ id: 345,
                                    package_id: @registry_package.id,
                                    name: "1.0.0",
                                    description: "test description",
                                    blob_store: "S3",
                                    ecosystem: Ecosystem::CONTAINER,
                                    created_at: Google::Protobuf::Timestamp.new,
                                    updated_at: Google::Protobuf::Timestamp.new,
                                    container_metadata: @version_metadata })

    @package_version1 = Version.new({ id: 3456,
                                      package_id: @registry_package1.id,
                                      name: "1.0.0",
                                      description: "test description",
                                      blob_store: "S3",
                                      ecosystem: Ecosystem::CONTAINER,
                                      created_at: Google::Protobuf::Timestamp.new,
                                      updated_at: Google::Protobuf::Timestamp.new,
                                      container_metadata: @version_metadata })
  end

  test "payload contains package hash" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :published, actor_id: @owner.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected = {
        id: @registry_package.id,
        name: @registry_package.name,
        namespace: @org.name,
        ecosystem: "CONTAINER",
        html_url: "https://github.com/#{@registry_package.namespace}/packages/#{@registry_package.id}",
        created_at: @registry_package.created_at.to_time.utc.xmlschema,
        updated_at: @registry_package.updated_at.to_time.utc.xmlschema,
    }

    actual = v3[:package]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload with symlink contains package hash and doesn't recurse" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package1.to_h,
                                            version: @package_version1.to_h, action: :published, actor_id: @owner.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected = {
        id: @registry_package1.id,
        name: @registry_package1.name,
        namespace: @org.name,
        ecosystem: "CONTAINER",
        html_url: "https://github.com/#{@registry_package.namespace}/packages/#{@registry_package1.id}",
        created_at: @registry_package1.created_at.to_time.utc.xmlschema,
        updated_at: @registry_package1.updated_at.to_time.utc.xmlschema,
    }

    actual = v3[:package]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
    body = v3[:package][:package_version][:body]
    assert_nothing_raised do
      body.to_json
    end
  end

  test "payload contains package_version hash" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :published, actor_id: @owner.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected = {
        id: @package_version.id,
        name: "1.0.0",
        description: "test description",
        blob_store: "S3",
        created_at: @package_version.created_at.to_time.utc.xmlschema,
        updated_at: @package_version.updated_at.to_time.utc.xmlschema,
        html_url: "https://github.com/#{@registry_package.namespace}/packages/#{@registry_package.id}?version=#{@package_version.id}",
    }

    actual = v3[:package][:package_version]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains package_version metadata hash" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :published, actor_id: @owner.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected_tag = {
        name: "asdf",
        digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c47272962dd60f71fc9",
    }

    actual = v3[:package][:package_version][:container_metadata]
    refute_nil actual, "expected version metadata but field was empty"

    refute_nil actual[:tag], "expected to see tag as part of the version metadata"
    expected_tag.each do |key, value|
      assert_equal value, actual[:tag][key], "Unexpected value for :#{key}"
    end

    expected_manifest = {
        uri: "http://github.com",
        digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c4727296asdf0f71fc9",
    }

    refute_nil actual[:manifest], "expected to see manifest as part of the version metadata"
    expected_manifest.each do |key, value|
      assert_equal value, actual[:manifest][key], "Unexpected value for :#{key}"
    end

    expected_labels = {
        description: "test data"
    }

    refute_nil actual[:labels], "expected to see manifest as part of the version metadata"
    expected_labels.each do |key, value|
      assert_equal value, actual[:labels][key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains organization hash" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :published, actor_id: @owner.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:organization_hash, @org)

    actual = v3[:organization]
    expected.each do |key, value|
      if value.nil?
        assert_nil actual[key], "Expected nil value for :#{key}"
      else
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end
  end

  test "payload contains sender hash" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :published, actor_id: @contributor.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_user_hash, @contributor)

    actual = v3[:sender]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains action type" do
    event = Hook::Event::PackageV2Event.new(registry_package: @registry_package.to_h,
                                            version: @package_version.to_h, action: :updated, actor_id: @contributor.id)
    payload = Hook::Payload::PackageV2Payload.new event
    v3 = payload.to_hash
    assert_equal :updated, v3[:action]
  end
end
