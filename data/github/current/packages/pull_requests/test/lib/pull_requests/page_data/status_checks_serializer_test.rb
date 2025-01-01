# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    class StatusChecksSerializerTest < GitHub::TestCase
      include UrlHelper
      include StatusHelper

      fixtures do
        @owner = create(:user, login: "wiseguy")

        @repo = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
        branch_attributes = {
          name: "master",
          creator: @owner,
          required_status_checks_enforcement_level: :non_admins,
        }
        @protected_branch = @repo.protected_branches.create(branch_attributes)
        @status_check = RequiredStatusCheck.new(
          protected_branch: @protected_branch,
          context: "Testing",
        )
        @status_check.save!

        @pull = create(:pull_request,
          repository: @repo,
          base_repository: @repo,
          base_user: @repo.owner,
          base_ref: "master",
          head_repository: @repo,
          head_user: @repo.owner,
          head_ref: "topic",
          user: @owner,
        )

        @pull_for_actions_check_suite = create(:pull_request,
          repository: @repo,
          base_repository: @repo,
          base_user: @repo.owner,
          base_ref: "master",
          head_repository: @repo,
          head_user: @repo.owner,
          head_ref: "rename-topic",
          user: @owner,
        )

        # status context
        @oauth_application = create(:oauth_application, name: "Lofty-CI", url: "https://lofty-ci.com/")
        @status_context = create(:status,
          oauth_application: @oauth_application,
          repository: @repo,
          creator: @repo.owner,
          sha: @pull.head_sha,
          context: "context1",
          state: "success",
          description: "yeah",
          target_url: "https://github.com/",
        )

        # check run
        GitHub.stubs(:actions_enabled?).returns(true) # To make sure the actions check suites create a workflow job run

        @github_app = create :integration, default_permissions: { "checks" => :write }
        @check_suite = create(:check_suite, repository: @repo, github_app: @github_app, head_sha: @pull.head_sha)
        @check_run = create(:check_run, name: "foo", check_suite: @check_suite, status: :completed, completed_at: Time.now, conclusion: :success)

        make_trusted_oauth_apps_owner
        @launch_app = create(:launch_integration)
        @actions_check_suite = create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull_for_actions_check_suite.head_sha)
        @success_actions_check_run = create(:check_run_for_actions_app, :with_steps, :success, check_suite: @actions_check_suite)
        @failure_actions_check_run = create(:check_run_for_actions_app, :with_steps, :failure, check_suite: @actions_check_suite)
      end

      setup do
        GitHub.stubs(:launch_github_app).returns(@launch_app)
      end

      test "serializes statusContexts, checkRuns, RequiredStatusChecks, and InMemoryRequiredStatusChecks" do
        merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)

        rule_config = @protected_branch.required_status_checks_policy
        required_status_check = RequiredStatusCheck.new(protected_branch: @protected_branch, context: "plain text")
        in_memory_check = InMemoryRequiredStatusCheck.normalize_status_checks(rule_config, rule_config.param("required_status_checks"))
        wrapped_run = CombinedStatus::CheckRunAdapter.new(@check_run)

        # added this for enterprise mode to not create a second InMemoryRequiredStatusCheck
        PullRequest::MergeStatus.any_instance.stubs(:target_branch_policy_evaluator).returns(false)

        status_checks = merge_button_view.combined_status.status_checks + in_memory_check + [required_status_check]

        # RequiredStatusChecks and InMemoryRequiredStatusCheck use Time.now so freezing for tests
        freeze_time
        serializer = PullRequests::PageData::StatusChecksSerializer.new(
          status_checks: status_checks,
          pull_request: @pull,
          pull_request_pending_workflow_approval_summary: nil,
          avatar_size: nil,
        )
        json_payload = {
          "aliveChannels" => {
            "commitHeadShaChannel" => GitHub::WebSocket::Channels.signed_commit(@pull.base_repository, @pull.head_sha)
          },
          "statusChecks" => [
            { "description" => T.must(in_memory_check[0]).description,
              "durationInSeconds" => T.must(in_memory_check[0]).duration_in_seconds,
              "stateChangedAt" => T.must(in_memory_check[0]).state_changed_at.to_time,
              "isRequired" => true,
              "displayName" => T.must(in_memory_check[0]).context,
              "state" => T.must(in_memory_check[0]).state.upcase,
              "targetUrl" => nil,
              "avatarUrl" => nil,
              "additionalContext" => additional_status_check_context(T.must(in_memory_check[0]).state, T.must(in_memory_check[0]).duration_in_seconds),
              "copilotCheckRunFailureContext" => nil,
            },
            { "description" => required_status_check.description,
              "durationInSeconds" => required_status_check.duration_in_seconds,
              "stateChangedAt" => required_status_check.state_changed_at.to_time,
              "isRequired" => true,
              "displayName" => required_status_check.context,
              "state" => required_status_check.state.upcase,
              "targetUrl" => nil,
              "avatarUrl" => nil,
              "additionalContext" => additional_status_check_context(required_status_check.state, required_status_check.duration_in_seconds),
              "copilotCheckRunFailureContext" => nil,
            },
            { "description" => @status_context.description,
              "durationInSeconds" => @status_context.duration_in_seconds,
              "stateChangedAt" => @status_context.created_at.to_time,
              "isRequired" => false,
              "displayName" => @status_context.contextual_name,
              "state" => @status_context.state.upcase,
              "targetUrl" => @status_context.target_url,
              "avatarUrl" => @status_context.application.preferred_avatar_url(size: 40),
              "additionalContext" => additional_status_check_context(@status_context.state, @status_context.duration_in_seconds),
              "copilotCheckRunFailureContext" => nil,
            },
            { "description" => wrapped_run.description,
              "durationInSeconds" => wrapped_run.duration_in_seconds,
              "stateChangedAt" => wrapped_run.state_changed_at.to_time,
              "isRequired" => false,
              "displayName" => wrapped_run.context,
              "state" => wrapped_run.state.upcase,
              "targetUrl" => wrapped_run.target_url(pull: @pull),
              "avatarUrl" => wrapped_run.creator.primary_avatar_url(40),
              "additionalContext" => additional_status_check_context(wrapped_run.state, wrapped_run.duration_in_seconds),
              "copilotCheckRunFailureContext" => nil,
            },
          ],
         "statusRollup" => {
            "summary" => [
              { "count" => 2, "state" => "SUCCESS" },
              { "count" => 2, "state" => "EXPECTED" },
            ],
            "combinedState" => "PENDING",
            "pendingWorkflowApprovalRollup" => nil,
          }
        }
        assert_equal json_payload.to_json, serializer.to_hash.to_json
      end

      context "Copilot check run failure context" do
        test "serializes context for failed actions check runs" do
          assert_predicate @failure_actions_check_run, :is_actions_check_run?

          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull_for_actions_check_suite, current_user: @pull_for_actions_check_suite.user)
          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks:,
            pull_request: @pull_for_actions_check_suite,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
            include_copilot_check_run_failure_context: true,
          )

          json_payload = serializer.to_hash.to_json
          assert_includes json_payload, "\"copilotCheckRunFailureContext\":{\"jobId\":#{@failure_actions_check_run.id}}"
        end

        test "does not serialize context for non-failed actions check runs" do
          assert_predicate @success_actions_check_run, :is_actions_check_run?

          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull_for_actions_check_suite, current_user: @pull_for_actions_check_suite.user)
          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks:,
            pull_request: @pull_for_actions_check_suite,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
            include_copilot_check_run_failure_context: false,
          )

          json_payload = serializer.to_hash.to_json
          refute_includes json_payload, "\"copilotCheckRunFailureContext\":{\"jobId\":#{@success_actions_check_run.id}}"
        end

        test "does not serialize context for failed actions check runs when include_copilot_check_run_failure_context is false" do
          assert_predicate @failure_actions_check_run, :is_actions_check_run?

          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull_for_actions_check_suite, current_user: @pull_for_actions_check_suite.user)
          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks:,
            pull_request: @pull_for_actions_check_suite,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
            include_copilot_check_run_failure_context: false,
          )

          json_payload = serializer.to_hash.to_json
          refute_includes json_payload, "\"copilotCheckRunFailureContext\":{\"jobId\":#{@failure_actions_check_run.id}}"
        end

        test "does not serialize context for failed actions check runs without a workflow job run" do
          check_run = create(:check_run_for_actions_app, :with_steps, :success, check_suite: @check_suite)
          assert_predicate check_run, :is_actions_check_run?
          refute_predicate check_run.workflow_job_run, :present?

          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)
          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks: status_checks,
            pull_request: @pull,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
            include_copilot_check_run_failure_context: true,
          )

          json_payload = serializer.to_hash.to_json
          refute_includes json_payload, "\"copilotCheckRunFailureContext\":{\"jobId\":#{check_run.id}}"
        end

        test "does not serialize context for non-actions check runs" do
          refute_predicate @check_run, :is_actions_check_run?

          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)
          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks: status_checks,
            pull_request: @pull,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
            include_copilot_check_run_failure_context: true,
          )

          json_payload = serializer.to_hash.to_json
          refute_includes json_payload, "\"copilotCheckRunFailureContext\":{\"jobId\":#{@check_run.id}}"
        end
      end

      context "workflows pending approval" do
        test "when there are workflows pending approval, returns the approval data" do
          create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)
          pull_request_pending_workflow_approval_summary = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner)
          status_checks = []

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks: status_checks,
            pull_request: @pull,
            pull_request_pending_workflow_approval_summary: pull_request_pending_workflow_approval_summary,
            avatar_size: nil,
          )

          workflow_approval_data = {
            "workflowsRequiringApprovalCount" => 1,
            "viewerCanApproveWorkflowRuns" => true,
            "hasExpiredWorkflowRuns" => false,
            "approvalRequiredMessage" => "Users without write permissions need approval to run workflows.",
            "helpLink" => "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks",
          }

          assert_equal workflow_approval_data, serializer.to_hash["statusRollup"]["pendingWorkflowApprovalRollup"]
        end

        test "when there are workflows pending approval and all checks pass, it returns the correct combinedState" do
          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)
          create(:check_run, name: "success", check_suite: @check_suite, status: :completed, completed_at: Time.now, conclusion: :success)
          create(:check_run, name: "success_2", check_suite: @check_suite, status: :completed, completed_at: Time.now, conclusion: :success)

          status_checks = merge_button_view.combined_status.status_checks
          create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)
          pull_request_pending_workflow_approval_summary = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner)

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks: status_checks,
            pull_request: @pull,
            pull_request_pending_workflow_approval_summary: pull_request_pending_workflow_approval_summary,
            avatar_size: nil,
          )

          workflow_approval_data = {
            "workflowsRequiringApprovalCount" => 1,
            "viewerCanApproveWorkflowRuns" => true,
            "hasExpiredWorkflowRuns" => false,
            "approvalRequiredMessage" => "Users without write permissions need approval to run workflows.",
            "helpLink" => "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks",
          }

          assert_equal workflow_approval_data, serializer.to_hash["statusRollup"]["pendingWorkflowApprovalRollup"]
          assert_equal "PENDING_APPROVAL", serializer.to_hash["statusRollup"]["combinedState"]
        end
      end

      test "handles serializing every possible status defined in StatusCheckConfig without type errors" do
        StatusCheckConfig::STATUSES.each do |status|
          assert_nothing_raised do
            PullRequests::PageData::StatusChecksSerializer::StatusCheckState.deserialize(status.enum.to_s.upcase)
          end
        end
      end

      test "additional context for in progress status" do
        Timecop.freeze do
          merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)
          status_context = create(:check_run, name: "in progress", check_suite: @check_suite, status: :in_progress, started_at: Time.now - 1.second)

          status_checks = merge_button_view.combined_status.status_checks

          serializer = PullRequests::PageData::StatusChecksSerializer.new(
            status_checks: status_checks,
            pull_request: @pull,
            pull_request_pending_workflow_approval_summary: nil,
            avatar_size: nil,
          )

          if GitHub.enterprise?
            assert_equal "Expected", T.must(serializer.to_hash["statusChecks"]).first["additionalContext"]
          else
            assert_equal "Started 1s ago", T.must(serializer.to_hash["statusChecks"]).first["additionalContext"]
          end
        end
      end

      test "additional context for pending status" do
        merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)
        status_context = create(:check_run, name: "in progress", check_suite: @check_suite, status: :pending)

        status_checks = merge_button_view.combined_status.status_checks

        serializer = PullRequests::PageData::StatusChecksSerializer.new(
          status_checks: status_checks,
          pull_request: @pull,
          pull_request_pending_workflow_approval_summary: nil,
          avatar_size: nil,
        )

        if GitHub.enterprise?
          assert_equal "Expected", T.must(serializer.to_hash["statusChecks"]).first["additionalContext"]
        else
          assert_equal "Waiting for status to be reported", T.must(serializer.to_hash["statusChecks"]).first["additionalContext"]
        end
      end
    end
  end
end
