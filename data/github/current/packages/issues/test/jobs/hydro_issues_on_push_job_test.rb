# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroIssuesOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include ConditionalAccess::FilterTestHelper
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @author = create(:user, login: "defunkt", plan: "bronze")
    @repo   = create(:repository, name: "hello-world", owner: @author, from_example: :simple)

    example_repo_snapshot

    @issue = create(:issue,
      repository: @repo,
      user:       @author,
    )
  end

  test "closes an issue or PR" do
    commit_data = {
      message: "fixes ##{@issue.number}",
      committer: @author
    }
    master = @repo.heads.find("master")
    before = @repo.ref_to_sha("master")
    commit = master.append_commit(commit_data, @author) do |files|
      files.add("name", "data")
    end

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: master.qualified_name, before: before, after: commit.oid }],
      pushed_at: 1.minute.ago,
      pusher: @author.login,
    }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")

    assert_equal "closed", @issue.reload.state
  end

  test "does not create referenced event for it's own merge commit" do
    pull_request = create(:pull_request, :with_mergeable_head, :disable_disk_access, repository: @repo)

    assert_difference -> { pull_request.repository.pushes.count }, 1 do
      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob, HydroIssuesOnPushJob]) do
        pull_request.merge
      end
    end

    refute IssueEvent.exists?(event: "referenced", issue_id: pull_request.issue.id)
  end

  test "noops for large push" do
    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: 1.minute.ago,
      pusher: @author.login,
    }
    HydroIssuesOnPushJob.any_instance.stubs(:large_push?).returns(true)
    HydroIssuesOnPushJob.any_instance.expects(:update_websocket).never
    Repositories::RefUpdate.any_instance.expects(:large_push?).never

    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
  end
end
