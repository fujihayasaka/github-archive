# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPackageEventTest < GitHub::TestCase
  include UploadableTestHelpers
  include HookEventTestHelper
  include GitHub::RegistryPackageHelper

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

    example_repo_snapshot
    @team.add_repository @repo, :pull


    @release = create :release, repository: @repo, tag_name: "1.0.0",
      author: @owner, state: :published, created_at: 1.month.ago,
      body: "*version 1*"

    @registry_package = @repo.packages.build(name: "test-docker-image", package_type: Registry::Package.symbolize_package_type(:docker))
    @package_version1 = @registry_package.package_versions.build(version: "1.0.0", release: @release, author: @owner, sha256: "1.0.0 sha256", size: 2067)
    @package_version1.files.build(size: 1, state: 1, filename: "test-docker-image-layer-1", sha256: "Image_blob_digest_1")
    @package_version2 = @registry_package.package_versions.build(version: "1.0.1", release: @release, author: @owner, sha256: "1.0.1 sha256", size: 8967)
    @package_version2.files.build(size: 1, state: 1, filename: "test-docker-image-layer-2", sha256: "Image_blob_digest_2")
    @package_version1.files.build(size: 1, state: 1, filename: "test-docker-image-config", sha256: "Image_config_blob_digest_1")
    assert @registry_package.save!

    @package_version1.metadata.create(name: "docker:schema:v2:image:manifest", value: "image 1.0.0 manifest")
    @package_version2.metadata.create(name: "docker:schema:v2:image:manifest", value: "image 1.0.1 manifest")

    @org_hook = create :hook, :org, events: %w(*)
  end

  context "#action" do
    test "is required" do
      assert_event_required_attributes Hook::Event::PackageEvent, :action
    end
  end

  context "#actor_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::PackageEvent, :actor_id
    end
  end

  context "#registry_package" do
    test "returns the specified registry_package" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :published, actor_id: @package_version1.author.id)
      assert_equal @registry_package.name, event.package.name
    end
  end

  context "#package_version" do
    test "returns the specified package_version" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :published, actor_id: @package_version1.author.id)
      assert_equal @package_version1.version, event.package_version.version
    end
  end

  context "#target_repository" do
    test "returns the specified target_repository" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :published, actor_id: @package_version1.author.id)
      assert_equal @repo, event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified actor" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :published, actor_id: @package_version1.author.id)
      assert_equal @package_version1.author, event.actor
    end
  end

  context "#action" do
    test "returns the specified action" do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :updated, actor_id: @package_version1.author.id)
      assert_equal :updated, event.action
    end
  end

  context "#deliverable?" do
    test "returns true if the package exists." do
      event = Hook::Event::PackageEvent.new(registry_package_id: @registry_package.id,
          package_version_id: @package_version1.id, action: :published, actor_id: @package_version1.author.id)
      assert event.deliverable?
    end
  end
end
