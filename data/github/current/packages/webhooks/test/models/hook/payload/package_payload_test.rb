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
class HookPayloadPackagePayloadTest < GitHub::TestCase
  include GitHub::RegistryPackageHelper
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
    @repo = create(:private_repository, owner: @owner, name: "test-docker-image", from_example: :repository_test_simple)
    @team.add_repository @repo, :pull

    example_repo_snapshot

    @release = create :release, repository: @repo, tag_name: "1.0.0",
      author: @owner, state: :published, created_at: 1.month.ago,
      body: "*version 1*"

    @registry_package = @repo.packages.build(name: "test-docker-image", package_type: Registry::Package.symbolize_package_type(:docker), registry_package_type: "docker")
    @package_version1 = @registry_package.package_versions.build(version: "1.0.0", release: @release, author: @owner, sha256: "1.0.0 sha256", size: 2067)
    @package_version1.metadata.build(name: Registry::Metadatum::KEYS[:SUMMARY], value: "docker image summary")
    @package_version1.metadata.build(name: "Custom-metadata-item-name", value: "The quick brown fox jumps over the lazy dog")
    @package_version1.metadata.build(name: "docker:schema:v2:image:manifest", value: "image 1.0.0 manifest")

    @package_version2 = @registry_package.package_versions.build(version: "1.0.1", release: @release, author: @owner, sha256: "1.0.1 sha256", size: 8967)
    assert @registry_package.save!

    @package_version1.metadata.set(Registry::Metadatum::KEYS[:README], "## This is the best version :dog2:")

    #v2 packages
    @registry_package_v2 = Package.new({ id: 123,
      namespace: @org.name,
      name: "test-docker-image",
      ecosystem: Ecosystem::CONTAINER,
      created_at: Google::Protobuf::Timestamp.new,
      updated_at: Google::Protobuf::Timestamp.new })

    @version_metadata = ContainerVersionMetadata.new({ tag: ContainerTag.new({ name: "asdf", digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c47272962dd60f71fc9" }),
                          manifest: ContainerManifest.new({ uri: "http://github.com", digest: "c9b1b535fdd91a9855fb7f82348177e5f019329a58c53c4727296asdf0f71fc9" }),
                          labels: ContainerLabels.new({ description: "test data" })
                          })

    @package_version_v2 = Version.new({ id: 345,
        package_id: @registry_package_v2.id,
        name: "1.0.0",
        description: "test description",
        blob_store: "S3",
        ecosystem: Ecosystem::CONTAINER,
        created_at: Google::Protobuf::Timestamp.new,
        updated_at: Google::Protobuf::Timestamp.new,
        container_metadata: @version_metadata })
  end
  context "v1 packages" do

    test "payload contains package hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        id: @registry_package.id,
        name: @registry_package.name,
        package_type: "docker",
        html_url: "https://github.com/#{@repo.nwo}/packages/#{@registry_package.id}",
        created_at: @registry_package.created_at,
        updated_at: @registry_package.updated_at,
      }

      actual = v3[:package]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains target OID when there is an associated Release" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        target_commitish: "master",
        target_oid: @release.tag.target.oid,
      }

      actual = v3[:package][:package_version]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains target OID when there is not an associated Release" do
      @package_version1.update!(release_id: nil)

      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        target_commitish: "master",
        target_oid: @repo.default_oid,
      }

      actual = v3[:package][:package_version]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains package_version hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        id: @package_version1.id,
        version: "1.0.0",
        summary: "docker image summary",
        prerelease: false,
        tag_name: "1.0.0",
        target_commitish: "master",
        target_oid: @release.tag.target.oid,
        manifest: "image 1.0.0 manifest",
        draft: false,
        created_at: @package_version1.created_at,
        updated_at: @package_version1.updated_at,
        html_url: "https://github.com/#{@repo.nwo}/packages/#{@registry_package.id}?version=#{@package_version1.version}",
        package_url: "#{GitHub.urls.registry_host_name(:docker)}/#{@repo.nwo}/#{@registry_package.name}:1.0.0",
      }

      actual = v3[:package][:package_version]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end


    test "payload contains package_version manifest for non-docker-images" do
      npm_package = Registry::Package.new(
        name: "npm-package",
        repository: @repo,
        owner: @repo.owner,
        package_type: :npm,
      )

      new_version = npm_package.package_versions.build(version: "1.0", author: @repo.owner, manifest: "This is the non-docker manifest", release: @release)
      npm_package.save!

      event = Hook::Event::PackageEvent.new(registry_package_id: npm_package.id,
            package_version_id: new_version.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        id: new_version.id,
        manifest: "This is the non-docker manifest",
      }

      actual = v3[:package][:package_version]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains release hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
        id: @release.id,
        tag_name: @release.tag_name,
        target_commitish: "master",
        prerelease: false,
        name: @release.name,
        draft: false,
        created_at: @release.created_at,
        published_at: @release.published_at,
        html_url: "https://github.com/#{@repo.nwo}/releases/tag/#{@release.tag_name}",
        url: "https://api.github.com/repos/#{@repo.nwo}/releases/#{@release.id}",
      }

      expected[:url] = "https://github.com/api/v3/repos/#{@repo.nwo}/releases/#{@release.id}" if GitHub.enterprise?

      actual = v3[:package][:package_version][:release]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains package_version metadata hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      metadata = [
        {
          "name": "Custom-metadata-item-name",
          "value": "The quick brown fox jumps over the lazy dog",
        },
      ]

      actual = v3[:package][:package_version][:metadata]
      metadata_map = actual.map { |metadatum| [metadatum[:name], metadatum] }.to_h
      assert_equal metadata.length, metadata_map.length, "expected to see #{metadata.length} items in the metadata collection"
      metadata.each do |expected|
        actual = metadata_map[expected[:name]]
        refute_nil actual, "Expected to see entry for #{expected[:name]} in metadata collection"
        expected.each do |key, value|
          assert_equal value, actual[key], "Unexpected value for :#{key}"
        end
      end
    end

    test "payload contains package_version body" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      assert_equal "## This is the best version :dog2:", v3[:package][:package_version][:body]
      assert_dom_equal "<div class=\"markdown-heading\"><h2 class=\"heading-element\">This is the best version 🐕</h2><a id=\"user-content-this-is-the-best-version-dog2\" class=\"anchor\" aria-label=\"Permalink: This is the best version :dog2:\" href=\"#this-is-the-best-version-dog2\"><svg class=\"octicon octicon-link\" viewBox=\"0 0 16 16\" version=\"1.1\" width=\"16\" height=\"16\" aria-hidden=\"true\"><path d=\"m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z\"></path></svg></a></div>", v3[:package][:package_version][:body_html]
    end

    test "payload contains repository hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = Api::Serializer.serialize(:simple_repository_hash, @repo)

      actual = v3[:repository]
      expected.each do |key, value|
        if value.nil?
          assert_nil actual[key], "Expected nil value for :#{key}"
        else
          assert_equal value, actual[key], "Unexpected value for :#{key}"
        end
      end
    end

    test "payload contains sender hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @contributor.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = Api::Serializer.serialize(:simple_user_hash, @contributor)

      actual = v3[:sender]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains package_files hash" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      files = @package_version1.files.map do |file| {
        "content_type": "application/octet-stream",
        "created_at": file.created_at,
        "id": file.id,
        "md5": file.md5,
        "name": file.name,
        "sha1": file.sha1,
        "sha256": file.sha256,
        "size": file.size,
        "state": file.state,
        "updated_at": file.updated_at,
      }
      end

      actual = v3[:package][:package_version][:package_files]
      assert_equal @package_version1.files.length, actual.length
      files_map = actual.map { |file| [file[:name], file] }.to_h
      files.each do |expected|
        actual = files_map[expected[:name]]
        refute_nil actual, "Expected to see entry for #{expected[:name]} in package_files collection"
        refute_nil actual[:download_url], "expected to see a non-nil vaue for download_url"
        expected.each do |key, value|
          if value.nil?
            assert_nil actual[key], "Expected nil value for :#{key}"
          else
            assert_equal value, actual[key], "Unexpected value for :#{key}"
          end
        end
      end
    end

    test "payload contains action type" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :updated, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      assert_equal :updated, v3[:action]
    end

    # Test the specific format of registry[:url] for the Docker registry.
    test "docker package payload correct registry information" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
            package_version_id: @package_version1.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      actual = v3[:package]

      expected = {
        name: "GitHub docker registry",
        type: "docker",
        url: "#{GitHub.urls.registry_url(:docker)}jessicard/test-docker-image",
        about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
        vendor: "GitHub Inc",
      }

      refute_nil actual[:registry]
      refute_empty actual[:registry]

      expected.each do |key, value|
        assert_equal value, actual[:registry][key]
      end
    end

    # Test the specific format of registry[:url] for the npm registry.
    test "npm package payload correct registry information" do
      npm_package = make_package_of_type("npm")
      event = Hook::Event::PackageEvent.new(registry_package_id: npm_package.id,
        package_version_id: npm_package.package_versions.first.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      actual = v3[:package]

      expected = {
        name: "GitHub npm registry",
        type: "npm",
        url: "#{GitHub.urls.registry_url(:npm)}@jessicard",
        about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
        vendor: "GitHub Inc",
      }

      refute_nil actual[:registry]
      refute_empty actual[:registry]

      expected.each do |key, value|
        assert_equal value, actual[:registry][key]
      end
    end

    # Test the generic format of registry[:url] used by Maven, Nuget and RubyGems
    test "package payload contains registry information" do
      gem = make_package_of_type("rubygems")
      event = Hook::Event::PackageEvent.new(registry_package_id: gem.id,
        package_version_id: gem.package_versions.first.id, action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      actual = v3[:package]

      expected = {
        name: "GitHub rubygems registry",
        type: "rubygems",
        url: "#{GitHub.urls.registry_url(:rubygems)}jessicard",
        about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
        vendor: "GitHub Inc",
      }

      refute_nil actual[:registry]
      refute_empty actual[:registry]

      expected.each do |key, value|
        assert_equal value, actual[:registry][key]
      end
    end
  end
  # Helper method to generate a package of specified type based off the @repo and @release created within fixture.
  #
  def make_package_of_type(type)
    package = @repo.packages.build name: "test-#{type}-package", repository: @repo, registry_package_type: type, package_type: type
    version = package.package_versions.build version: "v#{Time.now.usec}", release: @release, author: @owner
    version.files.build size: 1
    package.save!

    package
  end

  context "v2 packages" do
    test "payload contains package hash" do
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
          id: @registry_package_v2.id,
          name: @registry_package_v2.name,
          namespace: @org.name,
          ecosystem: "CONTAINER",
          html_url: "https://github.com/#{@registry_package_v2.namespace}/packages/#{@registry_package_v2.id}",
          created_at: @registry_package_v2.created_at.to_time.utc.xmlschema,
          updated_at: @registry_package_v2.updated_at.to_time.utc.xmlschema,
      }

      actual = v3[:package]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains package_version hash" do
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = {
          id: @package_version_v2.id,
          name: "1.0.0",
          version: "1.0.0",
          summary: "test description",
          description: "test description",
          created_at: @package_version_v2.created_at.to_time.utc.xmlschema,
          updated_at: @package_version_v2.updated_at.to_time.utc.xmlschema,
          html_url: "https://github.com/orgs/#{@registry_package_v2.namespace}/packages/container/#{@registry_package_v2.name}/#{@package_version_v2.id}",
          package_url: "#{GitHub.urls.registry_host_name(:containers)}/#{@registry_package_v2.namespace}/#{@registry_package_v2.name}:asdf",
      }

      actual = v3[:package][:package_version]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains package_version metadata hash" do
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
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
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :published, actor_id: @owner.id)
      payload = Hook::Payload::PackagePayload.new event
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
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :published, actor_id: @contributor.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash

      expected = Api::Serializer.serialize(:simple_user_hash, @contributor)

      actual = v3[:sender]
      expected.each do |key, value|
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end

    test "payload contains action type" do
      event = Hook::Event::PackageEvent.new(registry_package: @registry_package_v2.to_h,
                                              version: @package_version_v2.to_h, package_file: [], action: :updated, actor_id: @contributor.id)
      payload = Hook::Payload::PackagePayload.new event
      v3 = payload.to_hash
      assert_equal :updated, v3[:action]
    end
  end
end
