# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespaceCreatePrebuildTemplateDynamicWorkflowJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include ::Billing::CodespacesUsageHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @org = create(:credit_card_organization, plan: GitHub::Plan.business, admin: @user)
    GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].disable
    @repo = create(:repository, owner: @org, from_example: :refs_test)
    @commit_sha = "4c8124ffcf4039d292442eeccabdeca5af5c5017"
    @previous_sha = "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"
    @branch = "main"
    @location = "EastUs"
    @concurrency_modifier = "string"
    @job_args = {
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
    }
  end

  test "increments datadog if the job is forced to exit" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).raises(Aqueduct::Worker::JobKilled.new)

    perform_enqueued_jobs(only: [Codespaces::CreatePrebuildTemplateDynamicWorkflowJob]) do
      assert_raises Aqueduct::Worker::JobKilled do
        Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_later(
          **@job_args
        )
      end
    end

    assert_dogstats_increment "codespaces.create_prebuild_template_dynamic_workflow_job.dirty_exit", tags: ["vscs_target:production"]
  end

  test "calls CreatePrebuildTemplateDynamicWorkflowJob with expected arguments" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: nil,
      devcontainer_path: nil,
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      **@job_args
    )
  end

  test "calls CreatePrebuildTemplateDynamicWorkflowJob with expected arguments with warnings" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].enable(@repo)
    dc_contents = %{
      {
        "codespaces": {
          "repositories": [
            {
              "name": "#{@repo.nwo}",
              "permissions": {
                "contents": "read",
                "issues": "read"
              }
            }
          ]
        }
      }
    }

    @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
      files.add(".devcontainer/devcontainer.json", dc_contents)
    end
    branch = "master"

    configuration = create(:codespace_prebuild_configuration, repository: @repo, branch: branch)
    configuration.devcontainer_path = ".devcontainer/devcontainer.json"
    configuration.save!

    Codespaces::AllowedPermission.create!(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "metadata", action: "read",  is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
    Codespaces::AllowedPermission.create!(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "issues", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
    Codespaces::AllowedPermission.create!(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: ".devcontainer/devcontainer.json"
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: ".devcontainer/devcontainer.json",
    )
    configuration = Codespaces::PrebuildConfiguration.find_by(repository: @repo, branch: "master")
    assert configuration&.permission_granted?
  end

  test "calls CreatePrebuildTemplateDynamicWorkflowJob with expected arguments without warnings" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].enable(@repo)
    dc_contents = %{
      {
        "codespaces": {
          "repositories": [
            {
              "name": "#{@repo.nwo}",
              "permissions": {
                "contents": "read",
                "issues": "read"
              }
            }
          ]
        }
      }
    }

    @repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: @repo.owner }, @repo.owner) do |files|
      files.add(".devcontainer/devcontainer.json", dc_contents)
    end
    branch = "master"

    configuration = create(:codespace_prebuild_configuration, repository: @repo, branch: branch)
    configuration.devcontainer_path = ".devcontainer/devcontainer.json"
    configuration.save!

    Codespaces::AllowedPermission.create!(user: @user, repository: @repo, target_id: @repo.id, target_type: "Repository", resource: "metadata", action: "read",  is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: ".devcontainer/devcontainer.json"
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: ".devcontainer/devcontainer.json",
    )
    configuration = Codespaces::PrebuildConfiguration.find_by(repository: @repo, branch: "master")
    refute configuration&.permission_granted?
  end

  test "does not call CreatePrebuildTemplateDynamicWorkflowJob when usage limits have been exceeded" do
    GitHub.flipper[:codespaces_billing_free].disable

    configuration = create(:codespace_prebuild_configuration, repository: @repo, trigger: Codespaces::PrebuildConfiguration.triggers["configuration"])

    mock_codespaces_get_usage_breakdown(billable_owner: configuration.owner, entitlements_exhausted: true, budget_exhausted: true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).never

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      previous_sha: @previous_sha,
      configuration: configuration,
    )
  end

  test "does not call CreatePrebuildTemplateDynamicWorkflowJob if repo is nil" do
    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).never

    args_without_repo = @job_args.dup
    args_without_repo[:repository] = nil

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      **args_without_repo
    )
  end

  test "does not call CreatePrebuildTemplateDynamicWorkflowJob if repo is deleted" do
    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).never

    args_with_deleted_repo = @job_args.dup
    args_with_deleted_repo[:repository] = create(:repository, :soft_deleted)

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      **args_with_deleted_repo
    )
  end

  test "does not call CreatePrebuildTemplateDynamicWorkflow if trigger is configuration and prebuild hash doesn't change" do
    configuration = create(:codespace_prebuild_configuration, trigger: Codespaces::PrebuildConfiguration.triggers["configuration"])

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).never

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      previous_sha: @commit_sha,
      configuration: configuration,
    )
  end

  test "calls CreatePrebuildTemplateDynamicWorkflow if trigger is configuration and prebuild hash changes" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    configuration = create(:codespace_prebuild_configuration, trigger: Codespaces::PrebuildConfiguration.triggers["configuration"])

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: nil,
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      previous_sha: @previous_sha,
      configuration: configuration,
    )
  end

  test "calls CreatePrebuildTemplateDynamicWorkflow if trigger is configuration and previous sha is not defined" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    # This could happen if the prebuild is manually triggered by the user
    configuration = create(:codespace_prebuild_configuration, trigger: Codespaces::PrebuildConfiguration.triggers["configuration"])

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: nil,
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
    )
  end

  test "calls CreatePrebuildTemplateDynamicWorkflow if trigger is not configuration" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    configuration = create(:codespace_prebuild_configuration, trigger: Codespaces::PrebuildConfiguration.triggers["push"])

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).with(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      vscs_target: Codespaces::Vscs.default_target,
      vscs_target_url: nil,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
      devcontainer_path: nil,
    )

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      repository: @repo,
      locations: [@location],
      branch: @branch,
      commit_sha: @commit_sha,
      concurrency_modifier: @concurrency_modifier,
      configuration: configuration,
    )
  end

  test "increments datadog with the correct tags" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call)

    vscs_target = :production

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
      **@job_args
    )

    tags = [
      "class:codespaces/create_prebuild_template_dynamic_workflow_job"
    ]
    assert_dogstats_increment "active_job.performed", tags: tags
  end

  test "raises errors as expected" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).raises(Codespaces::Client::ConnectionFailed.new("OH NO"))

    assert_raises StandardError do
      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
        **@job_args
      )
    end
  end

  test "swallow invalid branch exception in job" do
    Codespaces::Prebuilds.stubs(:prebuild_usage_allowed?).returns(true)

    Codespaces::CreatePrebuildTemplateDynamicWorkflow.expects(:call).raises(Codespaces::CreatePrebuildTemplateDynamicWorkflow::InvalidBranchError.new("Invalid branch"))

    assert_nothing_raised do
      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.perform_now(
        **@job_args
      )
    end

    assert_dogstats_increment 1, "codespaces.create_prebuild_template_dynamic_workflow_job.invalid_branch"
  end
end unless GitHub.enterprise?
