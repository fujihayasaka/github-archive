# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../fake_create_result"

class WorkspaceEditor::Cloudspaces::PublicTest < GitHub::TestCase
  include CodespacesPlanFixtures
  include GitHub::ComponentTestHelpers

  setup do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
    Codespaces::Secret.stubs(:assemble).returns([])
    enable_feature_flag(:hadron_force_access)

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

  context "find_or_create" do
    test "creates a workspace editor cloudspace" do
      pull_request = new_pr!

      create_result = FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:)
      CloudEnvironments::Public.stubs(create: create_result)

      result = WorkspaceEditor::Cloudspaces::Public.find_or_create(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.workspace_editor_cloudspace
      assert result.workspace_editor_cloudspace&.cloud_environment
      refute result.found?
    end

    test "finds a workspace editor cloudspace on the PR" do
      pull_request = new_pr!
      create(:workspace_editor_cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
      result = WorkspaceEditor::Cloudspaces::Public.find_or_create(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.workspace_editor_cloudspace
      assert result.workspace_editor_cloudspace&.cloud_environment
      assert result.found?
    end
  end

  context "create_unique" do
    test "creates a workspace editor cloudspace" do
      pull_request = new_pr!

      create_result = FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:)
      CloudEnvironments::Public.stubs(create: create_result)

      result = WorkspaceEditor::Cloudspaces::Public.create_unique(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.workspace_editor_cloudspace
      assert result.workspace_editor_cloudspace&.cloud_environment
      refute result.found?
    end

    test "finds a workspace editor cloudspace on the PR" do
      disable_feature_flag(:hadron_cloudspace_force_create)
      pull_request = new_pr!
      create(:cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
      result = WorkspaceEditor::Cloudspaces::Public.create_unique(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.workspace_editor_cloudspace
      assert result.workspace_editor_cloudspace&.cloud_environment
      assert result.found?
    end
  end

  def new_pr!(branch_name = SecureRandom.hex)
    ref = @repository.heads.find_or_build("master")
    head_ref = @repository.heads.create(branch_name, ref.target, @owner)
    head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
      files.add("file001", "foo")
    end

    create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: "master", head_ref: branch_name)
  end
end
