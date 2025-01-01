# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"
require "test_helpers/launch/runner_scale_set_helper"

class Actions::RunnerScaleSetTest < GitHub::TestCase
  include Launch::SetupRunnerScaleSetHelper

  fixtures do
    @member = create :user
    @org = create :organization, admins: [@member]
    @repository = create :repository, owner: @org
    @enterprise = create :business, owners: [@member], organizations: [@org]
  end

  setup do
    @default_group = Actions::RunnerGroup.new(id: 1, name: "test-group", precreated: true)

    @default_statistics = GitHub::Launch::Services::Runnerscalesets::RunnerScaleSetStatistics.new(
      total_available_jobs: 1,
      total_acquired_jobs: 2,
      total_assigned_jobs: 3,
      total_running_jobs: 4,
      total_registered_runners: 5,
      total_busy_runners: 6,
      total_idle_runners: 7
    )

    @pb_scale_set = GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet.new(
      id: 1,
      name: "A scale set",
      runner_group_id: @default_group.id,
      runner_group_name: @default_group.name,
      status: "online",
      statistics: @default_statistics,
      labels: [GitHub::Launch::Services::Runnerscalesets::Label.new(name: "A scale set")]
    )

    @successful_get_response = GitHub::Launch::Services::Runnerscalesets::GetRunnerScaleSetResponse.new(
      runner_scale_set: @pb_scale_set,
    )

    @successful_list_response = GitHub::Launch::Services::Runnerscalesets::ListRunnerScaleSetsResponse.new(
      runner_scale_sets: [@pb_scale_set],
    )
  end

  def mock_list_runner_scale_sets_request
    Launch::Twirp::runner_scale_sets_client.expects(:list_scale_sets).returns(TwirpResponse.new(
      status: 200, value: @successful_list_response, call_succeeded: true
    ))
  end

  context ".get" do
    test "returns nil when a twirp error is raised" do
      mock_get_runner_scale_sets_request(success: false)

      runner = Actions::RunnerScaleSet.get(@repository, id: @pb_scale_set.id)
      assert_nil runner
    end

    test "returns nil for non-existent scale set" do
      mock_get_runner_scale_sets_request(success: false)

      runner = Actions::RunnerScaleSet.get(@repository, id: @pb_scale_set.id + 1)
      assert_nil runner
    end

    test "returns expected model instance for existent scale set" do
      mock_get_runner_scale_sets_request(success: true)
      scale_set = Actions::RunnerScaleSet.get(@repository, id: @pb_scale_set.id)

      refute_nil scale_set
      assert_equal @pb_scale_set.id, scale_set.id
      assert_equal @pb_scale_set.name, scale_set.name
      assert_equal @pb_scale_set.runner_group_id, scale_set.runner_group_id
      assert_equal @pb_scale_set.runner_group_name, scale_set.group_name
      assert_equal @pb_scale_set.status, scale_set.status

      assert_equal @pb_scale_set.statistics.total_available_jobs, scale_set.statistics.total_available_jobs
      assert_equal @pb_scale_set.statistics.total_acquired_jobs, scale_set.statistics.total_acquired_jobs
      assert_equal @pb_scale_set.statistics.total_assigned_jobs, scale_set.statistics.total_assigned_jobs
      assert_equal @pb_scale_set.statistics.total_running_jobs, scale_set.statistics.total_running_jobs
      assert_equal @pb_scale_set.statistics.total_registered_runners, scale_set.statistics.total_registered_runners
      assert_equal @pb_scale_set.statistics.total_busy_runners, scale_set.statistics.total_busy_runners
      assert_equal @pb_scale_set.statistics.total_idle_runners, scale_set.statistics.total_idle_runners

      assert_equal @pb_scale_set.labels, scale_set.labels
      refute_nil scale_set.owner
    end

    test "returns expected model instance with repository as owner" do
      mock_get_runner_scale_sets_request(success: true)
      scale_set = Actions::RunnerScaleSet.get(@repository, id: @pb_scale_set.id)

      refute_nil scale_set
      assert_equal @repository, scale_set.owner
    end

    test "returns expected model instance with organization as owner" do
      mock_get_runner_scale_sets_request(success: true)
      scale_set = Actions::RunnerScaleSet.get(@org, id: @pb_scale_set.id)

      refute_nil scale_set
      assert_equal @org, scale_set.owner
    end

    test "returns expected model instance with enterprise as owner" do
      mock_get_runner_scale_sets_request(success: true)
      scale_set = Actions::RunnerScaleSet.get(@enterprise, id: @pb_scale_set.id)

      refute_nil scale_set
      assert_equal @enterprise, scale_set.owner
    end
  end

  context ".for_entity" do
    test "returns empty array when a twirp error is raised" do
      Launch::Twirp::runner_scale_sets_client.expects(:list_scale_sets).returns(TwirpResponse.new(
        status: 500, call_succeeded: false
      ))

      scale_sets = Actions::RunnerScaleSet.for_entity(@repository)
      assert_empty scale_sets
    end

    test "returns list containing existent scale set" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@repository)

      refute_empty scale_sets

      assert_equal 1, scale_sets.count

      scale_set = scale_sets.first

      assert_equal @pb_scale_set.id, scale_set.id
      assert_equal @pb_scale_set.name, scale_set.name
      assert_equal @pb_scale_set.runner_group_id, scale_set.runner_group_id
      assert_equal @pb_scale_set.runner_group_name, scale_set.group_name
      assert_equal @pb_scale_set.status, scale_set.status

      assert_equal @pb_scale_set.statistics.total_available_jobs, scale_set.statistics.total_available_jobs
      assert_equal @pb_scale_set.statistics.total_acquired_jobs, scale_set.statistics.total_acquired_jobs
      assert_equal @pb_scale_set.statistics.total_assigned_jobs, scale_set.statistics.total_assigned_jobs
      assert_equal @pb_scale_set.statistics.total_running_jobs, scale_set.statistics.total_running_jobs
      assert_equal @pb_scale_set.statistics.total_registered_runners, scale_set.statistics.total_registered_runners
      assert_equal @pb_scale_set.statistics.total_busy_runners, scale_set.statistics.total_busy_runners
      assert_equal @pb_scale_set.statistics.total_idle_runners, scale_set.statistics.total_idle_runners

      assert_equal @pb_scale_set.labels, scale_set.labels
      refute_nil scale_set.owner
    end

    test "returns expected model instance with repository as owner" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@repository)

      refute_empty scale_sets

      scale_set = scale_sets.first

      assert_equal @repository, scale_set.owner
    end

    test "returns expected model instance with organization as owner" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@org)

      refute_empty scale_sets

      scale_set = scale_sets.first

      assert_equal @org, scale_set.owner
    end

    test "returns expected model instance with enterprise as owner" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@enterprise)

      refute_empty scale_sets

      scale_set = scale_sets.first

      assert_equal @enterprise, scale_set.owner
    end
  end

  context "#status" do
    test "returns 'disabled' for repo-level scale sets when policy does not allow them" do
      Repository.any_instance.stubs(:repo_self_hosted_runners_enabled?).returns(false)
      mock_list_runner_scale_sets_request

      @org.disable_repo_self_hosted_runners(actor: @member)

      scale_sets = Actions::RunnerScaleSet.for_entity(@repository)
      refute_empty scale_sets

      scale_set = scale_sets.first
      assert_equal "disabled", scale_set.status
    end

    test "returns status returned by API if repo-level scale sets are allowed" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@repository)
      refute_empty scale_sets

      scale_set = scale_sets.first
      assert_equal "online", scale_set.status
    end

    test "returns the status returned by the API for org-level scale sets" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@org)
      refute_empty scale_sets

      scale_set = scale_sets.first
      assert_equal "online", scale_set.status
    end

    test "returns the status returned by the API for enterprise-level scale sets" do
      mock_list_runner_scale_sets_request
      scale_sets = Actions::RunnerScaleSet.for_entity(@enterprise)
      refute_empty scale_sets

      scale_set = scale_sets.first
      assert_equal "online", scale_set.status
    end
  end
end
