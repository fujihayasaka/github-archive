# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../fake_create_result"

module WorkspaceEditor::Cloudspaces
  class FindTest < GitHub::TestCase
    include CodespacesPlanFixtures

    setup do
      enable_feature_flag(:hadron_force_access)
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      Codespaces::Secret.stubs(:assemble).returns([])

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

    context "environment lookup", skip_enterprise: true do
      test "it doesn't find anything when there's no environment for the provided PR" do
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
        )

        refute result.workspace_editor_cloudspace
      end

      test "it finds the environment when one exists in the correct state on the PR" do
        create(:cloud_environment, owner: @owner, pull_request: @pull_request)
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
        )

        assert result.workspace_editor_cloudspace
      end

      test "it respects vscs_target when finding environments" do
        prod = create(:cloud_environment, owner: @owner, pull_request: @pull_request, vscs_target: "production")
        development = create(:cloud_environment, owner: @owner, pull_request: @pull_request, vscs_target: "development")
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          vscs_target: "development",
        )

        assert_equal development, result.workspace_editor_cloudspace.cloud_environment
      end

      test "only finds created environments" do
        create(:cloud_environment, :failed, owner: @owner, pull_request: @pull_request)
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
        )

        refute result.workspace_editor_cloudspace
      end
    end

    context "environment refresh" do
      test "does not fetch the environment from the service when not requested" do
        create(:cloud_environment, owner: @owner, pull_request: @pull_request)
        Codespaces::VscsClient.any_instance.expects(:fetch_environment!).never
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
        )
      end

      test "fetches the environment from the service when requested" do
        create(:cloud_environment, owner: @owner, pull_request: @pull_request)
        Codespaces::VscsClient.any_instance.expects(:fetch_environment!).once
        result = WorkspaceEditor::Cloudspaces::Find.call(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: @pull_request.number,
          connect: true,
        )
      end
    end
  end
end
