# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../fake_create_result"

module WorkspaceEditor::Cloudspaces
  class CreateUniqueTest < GitHub::TestCase
    include CodespacesPlanFixtures

    setup do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      Codespaces::Secret.stubs(:assemble).returns([])
      enable_feature_flag(:hadron_force_access)

      @owner = create(:user)
      User.any_instance.stubs(:workspace_editor_preview_enabled?).returns(true)
      disable_feature_flag(:hadron_cloudspace_force_create)
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

    test "it only creates one cloudspace" do
      enable_feature_flag(:hadron_cloudspace_force_create, @owner)
      pull_request = new_pr!
      CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
      assert_changes -> { @owner.codespaces.include_deleted.only_workspace_editor_cloud_environments.count }, from: 0, to: 1 do
        result = WorkspaceEditor::Cloudspaces::Public.create_unique(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: pull_request.number,
          location: "EastUs",
          operation: @operation
        )
        refute result.found?
      end
    end

    context "with a found environment" do
      test "it ends the async operation immediately since we aren't acutally doing a create" do
        pull_request = new_pr!
        create(:cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
        CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
        result = WorkspaceEditor::Cloudspaces::Public.create_unique(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: pull_request.number,
          location: "EastUs",
          operation: @operation
        )
        assert @operation.ended?
      end
    end

    context "force create" do
      context "from `hadron_cloudspace_force_create` feature flag" do
        test "if an existing cloudspace is found, deprovision it and create a new one" do
          disable_feature_flag(:codespaces_hadron_no_delete_on_shutdown, @owner)
          enable_feature_flag(:hadron_cloudspace_force_create, @owner)

          pull_request = new_pr!
          existing = create(:cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
          CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation
          )

          refute result.found?
          assert existing.reload.deprovisioning?
        end

        test "if no existing cloudspace is found, also create a new one" do
          enable_feature_flag(:hadron_cloudspace_force_create, @owner)

          pull_request = new_pr!

          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation
          )

          refute result.found?
        end
      end

      context "from force_create param" do
        test "if an existing cloudspace is found, deprovision it and create a new one" do
          disable_feature_flag(:codespaces_hadron_no_delete_on_shutdown, @owner)

          pull_request = new_pr!

          existing = create(:cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
          CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation,
            force_create: true
          )

          refute result.found?
          assert existing.reload.deprovisioning?
        end

        test "if no existing cloudspace is found, also create a new one" do

          pull_request = new_pr!

          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation,
            force_create: true
          )

          refute result.found?
        end
      end
    end

    context "when cloud environment is in a bad state" do
      context "with a suspended environment" do
        test "it returns a newly created environment" do
          pull_request = new_pr!
          create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
          CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation
          )

          refute result.found?
        end

        test "it deprovisions the suspended environment normally" do
          disable_feature_flag(:codespaces_hadron_no_delete_on_shutdown, @owner)
          pull_request = new_pr!
          env = create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
          CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))

          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation
          )

          assert env.reload.deprovisioning?
        end

        test "it leaves the suspended environment when codespaces_hadron_no_delete_on_shutdown is enabled but still returns a new environment" do
          enable_feature_flag(:codespaces_hadron_no_delete_on_shutdown, @owner)
          pull_request = new_pr!
          env = create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
          CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))

          result = WorkspaceEditor::Cloudspaces::Public.create_unique(
            owner: @owner,
            repository_id: @repository.id,
            pull_request_number: pull_request.number,
            location: "EastUs",
            operation: @operation
          )

          refute result.found?
          refute env.reload.deprovisioning?
        end
      end
    end

    context "with a suspended environment" do
      test "it returns a newly created environment" do
        pull_request = new_pr!
        create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
        CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))
        result = WorkspaceEditor::Cloudspaces::Public.create_unique(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: pull_request.number,
          location: "EastUs",
          operation: @operation
        )

        refute result.found?
      end

      test "it deprovisions the suspended environment normally" do
        disable_feature_flag(:codespaces_hadron_no_delete_on_shutdown)
        pull_request = new_pr!
        env = create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
        CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))

        result = WorkspaceEditor::Cloudspaces::Public.create_unique(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: pull_request.number,
          location: "EastUs",
          operation: @operation
        )

        assert env.reload.deprovisioning?
      end

      test "it leaves the suspended environment when codespaces_hadron_no_delete_on_shutdown is enabled but still returns a new environment" do
        enable_feature_flag(:codespaces_hadron_no_delete_on_shutdown, @owner)
        pull_request = new_pr!
        env = create(:cloud_environment, :stopped_in_vscs, owner: @owner, repository: @repository, pull_request: pull_request)
        CloudEnvironments::Public.stubs(create: FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:))

        result = WorkspaceEditor::Cloudspaces::Public.create_unique(
          owner: @owner,
          repository_id: @repository.id,
          pull_request_number: pull_request.number,
          location: "EastUs",
          operation: @operation
        )

        refute result.found?
        refute env.reload.deprovisioning?
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
end
