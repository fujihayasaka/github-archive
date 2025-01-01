# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroIssuesOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include ConditionalAccess::FilterTestHelper
  include PlatformTestHelpers::InterfaceHelpers
  include GitHub::LoggerHelper


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

  context "logging" do
    test "doesn't log when then the FF is disabled" do
      disable_feature_flag(:log_commit_event_attribution_for_repo_owner)
      another_user = create(:user)
      @repo.add_member(another_user, action: :write)

      master = @repo.heads.find("master")
      before = @repo.ref_to_sha("master")

      commit_data = { message: "##{@issue.number}", committer: @author }
      another_commit_data = { message: "test", committer: another_user }

      first_commit = master.append_commit(commit_data, @author) do |files|
        files.add("name", "data")
      end

      second_commit = master.append_commit(another_commit_data, another_user) do |files|
        files.add("name", "data")
      end

      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: master.qualified_name, before: before, after: second_commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: another_user.login,
      }
      expected_log = {
        "Body": "HydroIssuesOnPushJob not triggered by the commit author",
        "gh.commit.author.is_pusher": false,
        "gh.commit.oid": first_commit.oid,
        "gh.commit.repository.id": first_commit.repository.id,
        "gh.issue.repository.id": @issue.repository.id
      }
      refute_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
      end

      reference_event = @issue.reload.timeline_events.last

      refute_equal @author.id, reference_event.actor_id
    end

    test "logs when the FF is enabled" do
      enable_feature_flag(:log_commit_event_attribution_for_repo_owner)
      another_user = create(:user)
      @repo.add_member(another_user, action: :write)

      master = @repo.heads.find("master")
      before = @repo.ref_to_sha("master")

      commit_data = { message: "##{@issue.number}", committer: @author }
      another_commit_data = { message: "test", committer: another_user }

      first_commit = master.append_commit(commit_data, @author) do |files|
        files.add("name", "data")
      end

      second_commit = master.append_commit(another_commit_data, another_user) do |files|
        files.add("name", "data")
      end

      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: master.qualified_name, before: before, after: second_commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: another_user.login,
      }
      expected_log = {
        "Body": "HydroIssuesOnPushJob not triggered by the commit author",
        "gh.commit.author.is_pusher": false,
        "gh.commit.oid": first_commit.oid,
        "gh.commit.repository.id": first_commit.repository.id,
        "gh.issue.repository.id": @issue.repository.id
      }
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
      end

      reference_event = @issue.reload.timeline_events.last

      refute_equal @author.id, reference_event.actor_id
    end

    test "logs a specific case where the owner is github" do
      enable_feature_flag(:log_commit_event_attribution)
      enable_feature_flag(:log_commit_event_attribution_for_repo_owner)

      owner = create(:organization, name: "github", admin: @author)
      repo = create(:repository, owner: owner, from_example: :simple)
      issue = create(:issue, repository: repo, user: @author)
      example_repo_snapshot

      another_user = create(:user)
      repo.add_member(another_user, action: :write)

      master = repo.heads.find("master")
      before = repo.ref_to_sha("master")

      commit_data = { message: "##{issue.number}", committer: @author }
      another_commit_data = { message: "test", committer: another_user }

      first_commit = master.append_commit(commit_data, @author) do |files|
        files.add("name", "data")
      end

      second_commit = master.append_commit(another_commit_data, another_user) do |files|
        files.add("name", "data")
      end

      issue.close(@author)

      message = {
        repository_id: repo.id,
        ref_updates: [{ ref: master.qualified_name, before: before, after: second_commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: another_user.login,
      }
      expected_log = {
        "Body": "HydroIssuesOnPushJob will not create a reference",
        "gh.commit.oid": first_commit.oid,
        "gh.commit.author.is_pusher": false,
        "gh.commit.repository.id": first_commit.repository.id,
        "gh.commit.in_merge_queue": false,
        "gh.issue.id": issue.id,
        "gh.issue.repository.id": issue.repository.id,
        "gh.issue.locked": false,
        "gh.issue.closed": true,
        "gh.issue.readable": true,
        "gh.reference_exists": false,
        "gh.pusher_lacks_api_context": true,
        "gh.pusher.is_user": another_user.is_a?(User),
        "gh.pusher.ip_address": "",
        "gh.pusher.name": another_user.display_login,
      }
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
      end

      reference_event = issue.reload.timeline_events.last

      refute_equal @author.id, reference_event.actor_id
    end

    test "logs ref information if the repository owner is github" do
      enable_feature_flag(:log_commit_event_attribution)

      owner = create(:organization, name: "github", admin: @author)
      repo = create(:repository, owner: owner, from_example: :simple)
      issue = create(:issue, repository: repo, user: @author)
      example_repo_snapshot

      another_user = create(:user)
      repo.add_member(another_user, action: :write)

      master = repo.heads.find("master")
      before = repo.ref_to_sha("master")

      commit_data = { message: "##{issue.number}", committer: @author }
      another_commit_data = { message: "test", committer: another_user }

      first_commit = master.append_commit(commit_data, @author) do |files|
        files.add("name", "data")
      end

      second_commit = master.append_commit(another_commit_data, another_user) do |files|
        files.add("name", "data")
      end

      issue.close(@author)

      message = {
        repository_id: repo.id,
        ref_updates: [{ ref: master.qualified_name, before: before, after: second_commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: another_user.login,
      }
      expected_log = {
        "Body": "HydroIssuesOnPushJob triggered",
        "gh.ref": master.qualified_name,
        "gh.ref.commits.count": 2,
        "gh.ref.commits.oid": "#{first_commit.oid}, #{second_commit.oid}"
      }
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
      end

      reference_event = issue.reload.timeline_events.last

      refute_equal @author.id, reference_event.actor_id
    end

    test "should work with allow list enabled" do

      owner = create :two_factor_credential_user
      org = create :business_plus_org, admins: [owner]
      active_org_entry = create :ip_allowlist_entry, owner: org, active: true, allow_list_value: "1.1.1.0/24"
      org.enable_ip_allowlist actor: owner
      org.enable_ip_allowlist_app_access actor: owner

      repo = create(:repository, name: "test", owner: org, from_example: :simple)

      issue = create(:issue,
        repository: repo,
        user:       owner,
      )

      commit_data = {
        message: "fixes ##{issue.number}",
        committer: owner
      }
      master = repo.heads.find("master")
      before = repo.ref_to_sha("master")
      commit = master.append_commit(commit_data, @author) do |files|
        files.add("name", "data")
      end

      message = {
        repository_id: repo.id,
        ref_updates: [{ ref: master.qualified_name, before: before, after: commit.oid }],
        pushed_at: 1.minute.ago,
        pusher: owner.login,
        user_programmatic_access_id: 1,
        request_context: {
          ip_address: "1.1.1.1"
        }
      }
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")

      assert_equal "closed", issue.reload.state
    end
  end
end
