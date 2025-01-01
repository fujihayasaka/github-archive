# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProductsNewsiesEmailsRepositoryAdvisoryTest < GitHub::TestCase
  include NewsiesHelper
  include RepositoriesTestHelper

  def grant(actor, action, subject)
    subject.send(:grant, actor, action)
  end

  def assert_notified(*users, subject:, type: "manual", handlers: %w[email web])
    users.each do |user|
      if handlers.include?("email")
        assert_delivered_email_notification(user, subject, type)
      end

      if handlers.include?("web")
        assert_delivered_web_notification(user, subject, type)
      end
    end
  end

  def refute_notified(*users, subject:, handlers: %w[email web], with_empty_thread: false)
    users.each do |user|
      if handlers.include?("email")
        refute_delivered_email_notification(user, subject)
      end

      if handlers.include?("web")
        refute_delivered_web_notification(user, subject, with_empty_thread: with_empty_thread)
      end
    end
  end

  def assert_subscribed(user, reason: nil)
    # This works as long as each test creates only one repository advisory.
    repository_advisory = RepositoryAdvisory.order(:id).last!
    subscription = repository_advisory.subscription_status(user)

    assert_predicate subscription, :subscribed?
    assert_equal reason.to_s, subscription.reason if reason
  end

  def refute_subscribed(user)
    # This works as long as each test creates only one repository advisory.
    repository_advisory = RepositoryAdvisory.order(:id).last!
    subscription = repository_advisory.subscription_status(user)

    refute_predicate subscription, :subscribed?
  end

  def clear_all_notifications
    Newsies::NotificationEntry.destroy_all
    Newsies::NotificationDelivery.delete_all
    ActionMailer::Base.deliveries.clear
  end

  def fetch_notification_entries(user, repo_adv)
    list = Newsies::List.to_object(repo_adv.repository)
    thread = Newsies::Thread.to_object(repo_adv, list: list)
    Newsies::NotificationEntry.for_thread(thread).for_user(user)
  end

  fixtures do
    # Create the users.
    users = %w[
      user_repo_owner
      user_repo_read_collaborator
      user_repo_write_collaborator
      user_repo_admin_collaborator
      org_admin
      org_read_member
      org_admin_member
      org_repo_read_collaborator
      org_repo_write_collaborator
      org_repo_admin_collaborator
      org_repo_read_team_member
      org_repo_write_team_member
      org_repo_admin_team_member
      org_repo_advisory_collaborator
      rando
    ].map do |login|
      user = create(:paid_user, :verified, login: login.dasherize)
      enable_notifications_for_user(user)
      instance_variable_set("@#{login}", user)
      user
    end

    # Create the organization.
    @org = create(:organization, admin: @org_admin, login: "org")

    # Create the organization's teams.
    %w[
      org_repo_read_team
      org_repo_write_team
      org_repo_admin_team
      org_repo_advisory_team
    ].each do |name|
      team = create(:public_team, organization: @org, name: name.dasherize)
      instance_variable_set("@#{name}", team)
    end

    # Personal Repository
    #
    # Create the repository.
    @user_repo = create(:repository, owner: @user_repo_owner, name: "user-repo")

    # Give repository collaborators different levels of access.
    grant(@user_repo_read_collaborator, :read, @user_repo)
    grant(@user_repo_write_collaborator, :write, @user_repo)
    grant(@user_repo_admin_collaborator, :admin, @user_repo)

    # Organizational Repository
    #
    # Give additional organization members access.
    grant(@org_read_member, :read, @org)
    grant(@org_admin_member, :admin, @org)

    # Create the repository.
    @org_repo = create(:repository, owner: @org, name: "org-repo")

    # Give repository collaborators different levels of access.
    grant(@org_repo_read_collaborator, :read, @org_repo)
    grant(@org_repo_write_collaborator, :write, @org_repo)
    grant(@org_repo_admin_collaborator, :admin, @org_repo)

    # Create a simple member of the organization (read access) who is a member
    # of a team (read access) that has read access to the repository.
    grant(@org_repo_read_team_member, :read, @org)
    grant(@org_repo_read_team_member, :read, @org_repo_read_team)
    grant(@org_repo_read_team, :read, @org_repo)

    # Create a simple member of the organization (read access) who is a member
    # of a team (read access) that has write access to the repository.
    grant(@org_repo_write_team_member, :read, @org)
    grant(@org_repo_write_team_member, :read, @org_repo_write_team)
    grant(@org_repo_write_team, :write, @org_repo)

    # Create a simple member of the organization (read access) who is a member
    # of a team (read access) that has admin access to the repository.
    grant(@org_repo_admin_team_member, :read, @org)
    grant(@org_repo_admin_team_member, :read, @org_repo_admin_team)
    grant(@org_repo_admin_team, :admin, @org_repo)

    # now we add two advisory collaborator users & teams
    # both have permissions on the org, but only one has
    # permissions on the repo
    grant(@org_repo_advisory_team, :read, @org_repo)
    grant(@org_repo_advisory_collaborator, :read, @org)
    grant(@org_repo_advisory_collaborator, :read, @org_repo_advisory_team)

    watch_repos(users: users, repos: [@org_repo, @user_repo])
  end

  setup do
    example_repo(:simple, @user_repo)
    example_repo(:simple, @org_repo)

    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  teardown do
    GitHub.newsies = @original_newsies
  end

  context "for a personal repository" do
    context "on creation" do
      test "notifies the repository owner" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_admin_collaborator,
        })

        assert_notified @user_repo_owner, subject: advisory
      end

      test "doesn't notify the author" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_owner,
        })

        refute_notified @user_repo_owner, subject: advisory
      end

      test "notifies admin collaborators" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_owner,
        })

        assert_notified @user_repo_admin_collaborator, subject: advisory
      end

      test "doesn't notify read or write collaborators" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_owner,
        })

        refute_notified @user_repo_read_collaborator,
                        @user_repo_write_collaborator,
                        subject: advisory
      end

      test "doesn't notify mentioned users lacking admin access" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_owner,
          body: "Hello, @user-repo-write-collaborator!",
        })

        refute_notified @user_repo_write_collaborator, subject: advisory
      end
    end

    context "commenting on an advisory" do
      test "only notifies the advisory thread author and advisory collaborators" do
        advisory = create(:repository_advisory, {
          repository: @user_repo,
          author: @user_repo_admin_collaborator,
        })
        comment = advisory.comments.create(body: "test", user: @user_repo_owner)

        assert_notified @user_repo_admin_collaborator, subject: comment, type: "comment"
        refute_notified @user_repo_read_collaborator, subject: comment
      end

      test "does not notify the advisory author if they are not a collaborator" do
        advisory = create(:accepted_pvd_repo_advisory, { repository: @user_repo, author: @rando })
        advisory.remove_collaborator(@rando, actor: @user_repo_owner)
        comment = advisory.comments.create(body: "test", user: @user_repo_owner)

        refute_notified @rando, subject: comment
      end
    end

    context "on publish" do
      test "notifies collaborators but not the owner" do
        advisory = create(:accepted_pvd_repo_advisory, { repository: @user_repo, author: @rando })
        advisory.set_published(actor: @user_repo_owner)

        event = advisory.events.published.last
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @user_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @user_repo_owner, subject: event
      end
    end

    context "on accept" do
      test "author and collaborators are notified" do
        advisory = create(:pending_pvd_repo_advisory, { repository: @user_repo, author: @rando })
        advisory.set_accepted(actor: @user_repo_owner)

        event = advisory.events.accepted.last
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @user_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @user_repo_owner, subject: event
      end
    end
  end

  context "for an organizational repository" do
    context "on creation" do
      test "notifies organization admins" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        assert_notified @org_admin_member, subject: advisory
      end

      test "respects granular security alert notification settings", skip_enterprise: true do
        assert_equal true, @org_admin_member.unwatch_repo(@org_repo)
        advisory = create(:repository_advisory, repository: @org_repo, author: @org_admin)

        refute_notified @org_admin_member, subject: advisory

        clear_all_notifications
        response = GitHub.newsies.subscribe_to_thread_types(@org_admin_member, @org_repo, [SecurityAlert]).value!
        assert_equal true, response

        advisory = create(:repository_advisory, repository: @org_repo, author: @org_admin)

        assert_notified @org_admin_member, subject: advisory
      end

      test "doesn't notify the author" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        refute_notified @org_admin, subject: advisory

        advisory = create(:pending_pvd_repo_advisory, {
          repository: @org_repo,
          author: @org_repo_read_collaborator
        })

        refute_notified @org_repo_read_collaborator, subject: advisory
      end

      test "doesn't notify non-admin organization members" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        refute_notified @org_read_member, subject: advisory
      end

      test "notifies repository admin collaborators" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        assert_notified @org_repo_admin_collaborator, subject: advisory
      end

      test "doesn't notify repository read/write collaborators" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        refute_notified @org_repo_read_collaborator,
                        @org_repo_write_collaborator,
                        subject: advisory
      end

      test "notifies users on repository admin teams" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        assert_notified @org_repo_admin_team_member, subject: advisory
      end

      test "doesn't notify users on repository read/write teams" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        refute_notified @org_repo_read_team_member,
                        @org_repo_write_team_member,
                        subject: advisory
      end

      test "doesn't notify mentioned users lacking admin access" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
          body: "Hello, @org-repo-write-collaborator!",
        })

        refute_notified @org_repo_write_collaborator, subject: advisory
      end

      test "doesn't notify users on mentioned teams lacking admin access" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
          body: "Hello, @org/org-repo-write-team!",
        })

        refute_notified @org_repo_write_team_member, subject: advisory
      end
    end

    context "on update" do
      test "updates subscriptions as mentions change" do
        repository_advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
          body: "Hello, @org-admin-member!",
        })

        assert_subscribed @org_admin_member, reason: :mention
        assert_subscribed @org_repo_admin_team_member, reason: :manual

        repository_advisory.update!(
          body: "Hello, @org-repo-admin-team-member!",
        )
        # Ignore job wait period and execute immediately
        perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob])

        assert_subscribed @org_admin_member # Still subscribed
        assert_subscribed @org_repo_admin_team_member, reason: :mention

        repository_advisory.update!(
          body: "Hello, @org-repo-write-team-member!",
        )

        refute_subscribed @org_repo_write_team_member # Unauthorized!

        repository_advisory.update!(
          body: "Hello, @org/org-repo-write-team!",
        )

        refute_subscribed @org_repo_write_team_member # Unauthorized!
      end

      test "when team collaborators are added, they are subscribed; when removed, they stop being subscribed." do
        repository_advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
          body: "Hello @org/@org-repo-advisory-team!",
        })

        refute_subscribed @org_repo_advisory_collaborator

        repository_advisory.add_collaborator(@org_repo_advisory_team)
        assert_subscribed @org_repo_advisory_collaborator

        # and then we remove the team
        repository_advisory.remove_collaborator(@org_repo_advisory_team)
        refute_subscribed @org_repo_advisory_collaborator
      end

      test "when collaborators are added, other subscribers are notified" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })
        advisory.add_collaborator(@org_repo_advisory_collaborator, actor: @org_admin)
        event = advisory.events.collaborator_added.last

        # existing collaborator, added collaborator
        assert_notified @org_admin_member, subject: event, type: "assign"
        assert_notified @org_repo_advisory_collaborator, subject: event, type: "assign"

        # collaborator that took the action, non-collaborator
        refute_notified @org_admin,
                        @org_repo_read_collaborator,
                        subject: event
      end

      test "when collaborators are removed, other subscribers and removed PVD submitter are notified" do
        advisory = create(:pending_pvd_repo_advisory, {
          repository: @org_repo,
          author: @rando,
        })
        advisory.add_collaborator(@org_repo_advisory_collaborator, actor: @org_admin)
        advisory.remove_collaborator(@rando, actor: @org_admin)
        event = advisory.events.collaborator_removed.last

        # Collaborators are notified (incl. PVR submitter)
        assert_notified @org_admin_member, subject: event, type: "state_change"
        # This user is subscribed to the repo rather than the advisory, so their notification reason reflects
        # that subscription rather than the individual reason given by the specific event.
        assert_notified @rando, subject: event, type: "state_change"

        refute_notified @org_admin, @org_repo_read_collaborator, subject: event
        refute_notified @org_repo_read_collaborator, subject: event

        advisory.remove_collaborator(@org_repo_advisory_collaborator, actor: @org_admin)
        event = advisory.events.collaborator_removed.last

        # existing collaborators
        assert_notified @org_admin_member, subject: event, type: "state_change"
        # Don't notify the non-author removed collaborator or the actor.
        refute_notified @org_repo_advisory_collaborator, @org_admin, subject: event
        refute_notified @org_repo_read_collaborator, subject: event
      end

      test "when collaborators are added or removed, a non-collaborator PVR author is not notified" do
        advisory = create(:pending_pvd_repo_advisory, {
          repository: @org_repo,
          author: @rando,
        })
        advisory.remove_collaborator(@rando, actor: @org_admin)

        advisory.add_collaborator(@org_repo_advisory_collaborator, actor: @org_admin)
        add_event = advisory.events.collaborator_added.last

        advisory.remove_collaborator(@org_repo_advisory_collaborator, actor: @org_admin)
        remove_event = advisory.events.collaborator_removed.last

        refute_notified @rando, subject: add_event
        refute_notified @rando, subject: remove_event
      end
    end

    context "commenting on an advisory" do
      test "only notifies the advisory thread author and advisory collaborators" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })
        advisory.add_collaborator(@org_repo_advisory_collaborator)
        comment = advisory.comments.create(body: "test", user: @org_admin_member)

        assert_notified @org_admin, subject: comment, type: "comment"
        assert_notified @org_repo_advisory_collaborator, subject: comment, type: "comment"

        refute_notified @org_repo_read_collaborator, subject: comment
        refute_notified @org_admin_member, subject: comment
      end

      test "does not notify the advisory author if they are not a collaborator" do
        advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @rando,
        })
        advisory.remove_collaborator(@rando)
        comment = advisory.comments.create(body: "test", user: @org_admin_member)

        refute_notified @rando, subject: comment
      end

      test "does not notify PVR advisory author if they are not a collaborator" do
        advisory = create(:accepted_pvd_repo_advisory, { repository: @org_repo, author: @rando })
        advisory.remove_collaborator(@rando, actor: @org_admin)
        comment = advisory.comments.create(body: "test", user: @org_admin)

        refute_notified @rando, subject: comment
      end
    end

    context "on deletion" do
      test "cleans up newsies data when destroyed" do
        repository_advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        GitHub.newsies.expects(:async_delete_all_for_thread).with(@org_repo, repository_advisory)
        repository_advisory.destroy
      end

      test "cleans up newsies data when destroyed and the repository no longer exists" do
        repository_advisory = create(:repository_advisory, {
          repository: @org_repo,
          author: @org_admin,
        })

        faux_repo = Repository.new
        @org_repo.delete

        Repository.expects(:new).returns(faux_repo)
        GitHub.newsies.expects(:async_delete_all_for_thread).with(faux_repo, repository_advisory)
        repository_advisory.reload.destroy
      end
    end

    context "on publish" do
      test "everyone is notified except for the publishing admin" do
        advisory = create(:accepted_pvd_repo_advisory, { repository: @org_repo, author: @rando })
        advisory.set_published(actor: @org_admin)

        event = advisory.events.published.last
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end

      test "PVR submitter is notified even if they are not a collaborator" do
        advisory = create(:accepted_pvd_repo_advisory, { repository: @org_repo, author: @rando })
        advisory.remove_collaborator(@rando, actor: @org_admin)
        advisory.set_published(actor: @org_admin)

        event = advisory.events.published.last
        # This user is subscribed to the repo rather than the advisory, so their notification reason reflects
        # that subscription rather than the individual reason given by the specific event.
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end
    end

    context "on accept" do
      test "repo admins and collaborators are notified" do
        advisory = create(:pending_pvd_repo_advisory, { repository: @org_repo, author: @rando })
        advisory.set_accepted(actor: @org_admin)

        event = advisory.events.accepted.last
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end

      test "PVR author is notified even if they are not a collaborator when watching the repo" do
        advisory = create(:pending_pvd_repo_advisory, { repository: @org_repo, author: @rando })
        advisory.remove_collaborator(@rando, actor: @org_admin)
        advisory.set_accepted(actor: @org_admin)

        event = advisory.events.accepted.last
        # Author is subscribed to the repo rather than the thread, so their notification reason reflects that.
        assert_notified @rando, subject: event, type: "state_change"
        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end

      test "PVR author is notified even if they are not a collaborator when not watching the repo" do
        not_watching_user = create(:user, :verified)
        enable_notifications_for_user(not_watching_user)

        advisory = create(:pending_pvd_repo_advisory, { repository: @org_repo, author: not_watching_user })
        advisory.remove_collaborator(not_watching_user, actor: @org_admin)
        advisory.set_accepted(actor: @org_admin)

        event = advisory.events.accepted.last
        assert_notified not_watching_user, subject: event, type: "state_change"
      end
    end

    context "on close" do
      test "other subscribers and non-collaborator author receive notifications" do
        advisory = create(:pending_pvd_repo_advisory, {
          repository: @org_repo,
          author: @rando,
        })
        advisory.remove_collaborator(@rando, actor: @org_admin)
        advisory.comment_and_close(@org_admin, "test")
        event = advisory.events.closed.last

        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        # Author is subscribed to the repo rather than the thread, so their notification reason reflects that.
        assert_notified @rando, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end
    end

    context "on reopen" do
      test "other subscribers and non-collaborator author receive notifications" do
        advisory = create(:pending_pvd_repo_advisory, {
          repository: @org_repo,
          author: @rando,
        })
        advisory.remove_collaborator(@rando, actor: @org_admin)
        advisory.comment_and_close(@org_admin, "test")
        advisory.comment_and_reopen(@org_admin, "test")
        event = advisory.events.reopened.last

        assert_notified @org_repo_admin_collaborator, subject: event, type: "state_change"
        # Author is subscribed to the repo rather than the thread, so their notification reason reflects that.
        assert_notified @rando, subject: event, type: "state_change"
        refute_notified @org_admin, subject: event
      end
    end
  end

  context "content" do
    test "verify notification content" do
      old_advisory_body = "Hello this is my advisory"
      advisory_description = "Very Technical Description Of The Advisory"
      comment_body = "Hello this is my comment"

      # created by the org-admin, the @org_admin_member should be auto subscribed
      ra = RepositoryAdvisory.create!({
        repository: @org_repo,
        author: @org_admin,
        body: old_advisory_body,
        description: advisory_description,
        title: Faker::Lorem.sentence,
        severity: :moderate,
      })

      # first we check the contents of the NotificationSummary, which is used
      # in the web ui
      entry = fetch_notification_entries(@org_admin_member, ra).first
      assert entry

      summary = entry.to_summary_hash
      summary_title = summary[:title]
      ra_summary_item = summary[:items]["RepositoryAdvisory:#{ra.id}"]

      assert_equal ra.title, summary_title
      assert_equal advisory_description, ra_summary_item["body"]

      # then we check the contents of the email that was sent
      # at a glance, it's not clear if there's a better way to do this,
      # so we just check inside the email deliveries object and assert
      # we should have at least *one* email
      assert_equal 3, ActionMailer::Base.deliveries.size
      ra_email = ActionMailer::Base.deliveries.last

      # then, we look in the email for the exact occurence of our body string
      assert ra_email.to_s.index(advisory_description)

      # Cool. Let's try with a comment. First, we create it:
      rac = ra.comments.create(body: comment_body, user: @org_admin)

      # new notifications on the same thread get "rolled up", so no new entries
      # are created. instead, we re-fetch the NotificationSummary
      summary = entry.reload.to_summary_hash

      rac_summary_item = summary[:items]["RepositoryAdvisoryComment:#{rac.id}"]
      assert_equal comment_body, rac_summary_item["body"]

      # as per email, we check to see there's another delivery
      assert_equal 6, ActionMailer::Base.deliveries.size
      rac_email = ActionMailer::Base.deliveries.last

      # and we re-repeat looking for the exact occurrence of our comment string
      assert rac_email.to_s.index(comment_body)
    end
  end
end
