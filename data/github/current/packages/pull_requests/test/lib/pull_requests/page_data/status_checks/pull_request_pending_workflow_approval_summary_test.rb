# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module StatusChecks
      class PullRequestPendingWorkflowApprovalSummaryTest < GitHub::TestCase

        fixtures do
          @owner = create(:user, login: "wiseguy")
          @rando = create(:user, login: "rando")

          @repo = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
          @public_repo = create(:repository, owner: @owner, name: "public", from_example: :review_comment_fork)

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

          @public_pull = create(:pull_request,
            repository: @public_repo,
            base_repository: @public_repo,
            base_user: @public_repo.owner,
            base_ref: "master",
            head_repository: @public_repo,
            head_user: @public_repo.owner,
            head_ref: "topic",
            user: @owner,
          )

          make_trusted_oauth_apps_owner
          @launch_app = create(:launch_integration)
        end

        setup do
          GitHub.stubs(:launch_github_app).returns(@launch_app)
        end

        context "returning approval data" do
          test "when there are workflows pending approval and none are expired" do
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup
            assert_equal 1, data&.workflowsRequiringApprovalCount
            assert data&.viewerCanApproveWorkflowRuns
            refute data&.hasExpiredWorkflowRuns
          end

          test "when there are workflows pending approval and some are expired" do
            Timecop.freeze do
              create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required, created_at: 1.month.ago - 1.day)
              create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

              data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup
              assert_equal 2, data&.workflowsRequiringApprovalCount
              assert data&.viewerCanApproveWorkflowRuns
              assert data&.hasExpiredWorkflowRuns
            end
          end

          test "when there are workflows pending approval and all are expired" do
            Timecop.freeze do
              create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required, created_at: 1.month.ago - 1.day)
              create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required, created_at: 2.months.ago)

              data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup
              assert_equal 2, data&.workflowsRequiringApprovalCount
              refute data&.viewerCanApproveWorkflowRuns
              assert data&.hasExpiredWorkflowRuns
            end
          end

          test "when there are workflows pending approval and there is no current user" do
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: nil).rollup
            assert_equal 1, data&.workflowsRequiringApprovalCount
            refute data&.viewerCanApproveWorkflowRuns
            refute data&.hasExpiredWorkflowRuns
          end

          test "when there are workflows pending approval and the current user cannot write to the repo" do
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @rando).rollup
            assert_equal 1, data&.workflowsRequiringApprovalCount
            refute data&.viewerCanApproveWorkflowRuns
            refute data&.hasExpiredWorkflowRuns
          end

          test "when the repository is private, returns the correct help link and approval message" do
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup
            assert_equal 1, data&.workflowsRequiringApprovalCount
            assert_equal "Users without write permissions need approval to run workflows.", data&.approvalRequiredMessage
            assert_equal "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks", data&.helpLink
          end

          test "when the repository is public, returns the correct help link and approval message" do
            create(:check_suite_for_actions_app, repository: @public_repo, head_sha: @public_pull.head_sha, conclusion: :action_required)

            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @public_pull, current_user: @owner).rollup
            assert_equal 1, data&.workflowsRequiringApprovalCount
            assert_equal "This workflow requires approval from a maintainer.", data&.approvalRequiredMessage
            assert_equal "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-public-forks", data&.helpLink
          end

          test "when there are no workflows pending approval, returns nil" do
            data = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup

            assert_nil data
          end

          test "query counts" do
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)
            create(:check_suite_for_actions_app, repository: @repo, head_sha: @pull.head_sha, conclusion: :action_required)

            assert_query_count(2, ignore_feature_flags: true) do
              PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull, current_user: @owner).rollup
            end
          end
        end
      end
    end
  end
end
