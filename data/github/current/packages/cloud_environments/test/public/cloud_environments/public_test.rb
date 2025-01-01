# typed: true
# frozen_string_literal: true

require "test_helper"

class CloudEnvironments::PublicTest < GitHub::TestCase
  include CodespacesPlanFixtures

  class FakeProvisioner < CloudEnvironments::Command
    def initialize(cloud_environment, **)
      @cloud_environment = cloud_environment
    end

    def perform
      @cloud_environment.update(guid: SecureRandom.uuid, state: :provisioned)
      ::Codespaces::Environment.from_json({ "id" => @cloud_environment.guid, "connection" => {} })
    end
  end

  setup do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
    Codespaces::Secret.stubs(:assemble).returns([])
    CloudEnvironments::Create.any_instance.stubs(:provisioner).returns(FakeProvisioner)

    @owner = create(:user)
    User.any_instance.stubs(:workspace_editor_preview_enabled?).returns(true)
    @owner.enable_feature_preview(:copilot_hadron_editor)
    @repository = create(:repository, owner: @owner, from_example: :simple)
    @master_head = @repository.heads.find_or_build(@repository.default_branch)
    head_ref = @repository.heads.create("patch-1", @master_head.target, @owner)
    head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
      files.add("file001", "foo")
    end
    @pull_request = create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: @repository.default_branch, head_ref: "patch-1")
    @operation = create(:codespaces_async_operation, operation: :create_codespace)
  end

  context "create" do
    test "creates a cloud environment" do
      git_ref = Codespaces::GetTargetRef.call(repository: @repository, name_or_oid: @pull_request.head_ref)
      result = CloudEnvironments::Public.create(
        attributes: {
          owner: @owner,
          repository_id: @repository.id,
          pull_request_id: @pull_request.id,
          ref: @pull_request.head_ref,
          oid: git_ref.target_oid,
          sku_name: "standardLinux",
          location: "EastUs",
        },
        operation: @operation,
        stats_tagger: CloudEnvironments::StatsTagger.new,
        environment_options: {},
        entry_point: :test_case
      )

      assert result.cloud_environment
      assert result.provisioned?
    end
  end
end
