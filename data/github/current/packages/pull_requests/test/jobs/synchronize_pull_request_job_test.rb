# typed: true
# frozen_string_literal: true

require "test_helper"

class SynchronizePullRequestJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "spookymona")
    @repo = create(:repository, owner: @user)
  end

  context "#perform" do
    test "reports to failbot on missing pull request" do
      Failbot.context.clear
      Failbot.expects(:report).with do |err, _|
        err.is_a?(ActiveRecord::RecordNotFound)
      end

      SynchronizePullRequestJob.perform_now(
        pull_request_id: 0,
        user: @user,
        installation: nil,
        repo: @repo,
        forced: false,
        ref: "master",
        before: nil,
        after: nil,
        push_options: nil
      )

      failbot_context = Failbot.squash_contexts(Failbot.context)
      assert_equal @repo.id, failbot_context["gh.repo.id"]
      assert_equal @user.id, failbot_context["gh.user.id"]
    end
  end

  context "logging or raising PullRequest::DetermineCodeownersError" do
    context "when pr_sync_log_determine_codeowners_errors feature flag is disabled" do
      test "raises PullRequest::DetermineCodeOwnersError" do
        GitHub.flipper[:pr_sync_log_determine_codeowners_errors].disable

        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        job = SynchronizePullRequestJob.new(
          pull_request_id: pull.id,
          user: @user,
          installation: nil,
          repo: @repo,
          forced: false,
          ref: "master",
          before: nil,
          after: nil,
          push_options: nil
        )

        # Job loads the PR by finding the ID, so we have to stub any_instance
        PullRequest.any_instance.expects(:synchronize!).raises(PullRequest::DetermineCodeownersError.new(nil))

        perform_enqueued_jobs(only: SynchronizePullRequestJob) do
          assert_raises(PullRequest::DetermineCodeownersError) do
            job.perform_now
          end
        end
      end
    end

    context "when pr_sync_log_determine_codeowners_errors feature flag is enabled" do
      test "logs PullRequest::DetermineCodeownersError" do
        GitHub.flipper[:pr_sync_log_determine_codeowners_errors].enable

        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        job = SynchronizePullRequestJob.new(
          pull_request_id: pull.id,
          user: @user,
          installation: nil,
          repo: @repo,
          forced: false,
          ref: "master",
          before: nil,
          after: nil,
          push_options: nil
        )

        # Job loads the PR by finding the ID, so we have to stub any_instance
        PullRequest.any_instance.expects(:synchronize!).raises(PullRequest::DetermineCodeownersError.new(nil))
        GitHub.logger.expects(:info).with("PullRequest::DetermineCodeownersError occurred during SynchronizePullRequestJob", any_parameters)

        perform_enqueued_jobs(only: SynchronizePullRequestJob) do
          job.perform_now
        end
      end
    end
  end
end
