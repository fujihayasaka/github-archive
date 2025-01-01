# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitMentionUserNotificationTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @sr       = create(:staff_admin_user, :verified, email: "simon@rozet.name", login: "sr")
    @rtomayko = create(:staff_admin_user, :verified, email: "rtomayko@github.com", login: "rtomayko")
    @kneath   = create(:staff_admin_user, :verified, email: "kneath@github.com", login: "kneath")
    @defunkt  = create(:staff_admin_user, :verified, email: "defunkt@github.com", login: "defunkt")
    @repo     = create(:repository, name: "github", owner: @sr)
    @rtomayko.watch_repo @repo
    @kneath.watch_repo   @repo
    @defunkt.watch_repo @repo
    [@rtomayko, @kneath, @sr, @defunkt].each do |user|
      GitHub.newsies.get_and_update_settings(user) do |settings|
        settings.participating_settings << "email"
      end
    end
  end

  setup do
    example_repo :commit_user_mentions, @repo

    ActionMailer::Base.deliveries.clear
  end

  def notify
    commit_oid = @repo.ref_to_sha("master")
    commits = @repo.commits.history(commit_oid)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns(commits)
    trigger_push_event(
      @repo.shard_path,
      @repo.owner.login,
      [["refs/heads/master", commits.last.oid, commits.first.oid]],
      Time.now,
      perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
    )
  end

  test "notifies all of the mentioned" do
    commit = @repo.commits.find("1be5f4658c7c8cf0edada58fff0625a7bd242da1")
    assert !GitHub.newsies.subscription_status(@defunkt, @repo, commit).valid?

    assert_difference "ActionMailer::Base.deliveries.size", 3 do
      assert_performed_with job: SubscribeAndNotifyJob do
        notify
      end
    end

    summary = NotificationSummary.by_thread(@repo, commit)
    assert summary.item(commit)

    mail = ActionMailer::Base.deliveries.find { |mail| mail.subject == "[sr/github] tell @defunkt (1be5f46)" }
    assert mail.present?
    assert_equal "#{@repo.name_with_owner}/commit/1be5f4658c7c8cf0edada58fff0625a7bd242da1@#{GitHub.host_name}", mail.message_id
    status = GitHub.newsies.subscription_status(@defunkt, @repo, commit).value
    assert status.valid?
    assert_equal "mention", status.reason
  end

  test "does not notify a commit author that mentions themselves" do
    metadata = { message: "Add @sr and @defunkt's changes", committer: @sr }

    oid    = @repo.heads.find("master").target_oid
    commit = @repo.commits.create(metadata, oid) {}

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      assert_performed_with job: SubscribeAndNotifyJob do
        only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
        perform_enqueued_jobs(only: only) do
          Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])
          after, before = @repo.rpc.rev_list(commit.oid).take(2)
          trigger_push_event(
            @repo.shard_path,
            @repo.owner.login,
            [["refs/heads/master", before, after]],
            Time.now,
            perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
          )
        end
      end
    end

    status = GitHub.newsies.subscription_status(@sr, @repo, commit).value
    assert status.valid?
    assert_equal "author", status.reason

    status = GitHub.newsies.subscription_status(@defunkt, @repo, commit).value
    assert status.valid?
    assert_equal "mention", status.reason
  end

  test "notify only once for sha1" do
    assert_performed_with job: SubscribeAndNotifyJob do
      notify
    end

    count = CommitMention.count

    assert_no_performed_jobs(only: SubscribeAndNotifyJob) do
      notify
    end

    assert_equal count, CommitMention.count
  end

  test "only notify users with read access" do
    @repo.update!(public: false)
    @repo.add_member @rtomayko
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      assert_performed_with job: SubscribeAndNotifyJob do
        notify
      end
    end
  end

  test "respects user blocking author" do
    @rtomayko.block(@sr)
    assert_difference "ActionMailer::Base.deliveries.size", 2 do
      assert_performed_with job: SubscribeAndNotifyJob do
        notify
      end
    end
  end

  test "respects author blocking user" do
    @sr.block(@rtomayko)
    assert_difference "ActionMailer::Base.deliveries.size", 2 do
      assert_performed_with job: SubscribeAndNotifyJob do
        notify
      end
    end
  end
end
