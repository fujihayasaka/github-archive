# typed: false
# frozen_string_literal: true

require "test_helper"

class DiscussionPostTest < GitHub::TestCase
  include NewsiesHelper
  include StringFromBinaryTestHelper

  fixtures do
    @team = create(:team, privacy: :closed)
    @team_member = create(:user, :verified)
    @team.add_member(@team_member)
    @org = @team.organization
    @org_member = create(:verified_user)
    @org.add_member(@org_member)
    only = [SubscribeAndNotifyJob]
    @post = perform_enqueued_jobs(only: only) { create(:discussion_post, team: @team) }
    @random_installation = make_integration_installation(target: @org,
      name: "random-bot", permissions: { members: :read })
    @installation_with_read_permission = make_integration_installation(target: @org,
      name: "bot-with-read-permission", permissions: { team_discussions: :read })
    @installation_with_write_permission = make_integration_installation(target: @org,
      name: "bot-with-write-permission", permissions: { team_discussions: :write })
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "validations" do
    test "requires non-empty body" do
      post = build(:discussion_post, body: "")
      refute post.valid?
      assert_equal "Body cannot be blank", post.errors.full_messages.to_sentence
    end

    test "requires body that is more than just whitespace" do
      post = build(:discussion_post, body: "   ")
      refute post.valid?
      assert_equal "Body cannot be blank", post.errors.full_messages.to_sentence
    end

    test "limits title to 256 characters (1024 bytes/4)" do
      post = build(:discussion_post, title: "a" * 1025)
      refute post.valid?
      assert_equal "Title is too long (maximum is 256 characters)", post.errors.full_messages.to_sentence
    end
  end

  context "#body_html" do
    test "renders team-mentions" do
      @post.body = "@#{@team.combined_slug}"
      team_url = UrlHelpers.team_url(@org, @team,
        host: GitHub.host_name, protocol: "https")
      assert_match %r|<a (.*)href=\"#{team_url}\"(.*)>@#{@team.combined_slug}</a>|,
        @post.body_html
    end
  end

  context "human-readable sequence numbers" do
    test "receives the first sequence number as the first post for the team" do
      assert_equal 1, @post[:number]
    end

    test "receives the next sequence number when there are existing posts for the team" do
      team = create(:team)
      2.times { create(:discussion_post, team: team) }
      assert_equal 3, create(:discussion_post, team: team)[:number]
    end

    test "does not reuse sequence numbers" do
      team = create(:team)
      2.times { create(:discussion_post, team: team) }
      team.discussion_posts.last.destroy
      assert_equal 1, team.discussion_posts.count
      assert_equal 3, create(:discussion_post, team: team)[:number]
    end

    test "uses different sequences for different teams" do
      assert_equal 1, create(:discussion_post, team: create(:team))[:number]
      assert_equal 1, create(:discussion_post, team: create(:team))[:number]
    end
  end

  context "#title_changed?" do
    test "false if UTF-8 title doesn't change" do
      post = create(:discussion_post, team: @team, title: "caractères spéciaux")
      refute post.title_changed?

      post.title = "caractères spéciaux"
      refute post.title_changed?
    end

    test "true if UTF-8 title changes" do
      post = create(:discussion_post, team: @team, title: "caractères spéciaux")
      refute post.title_changed?

      post.title = "caractères spéciaux - foo bar"
      assert post.title_changed?
    end
  end

  context "notifications" do
    if GitHub.spamminess_check_enabled?
      test "does not notify anyone for post creation by spammy user" do
        spammy_team_member = create(:user, spammy: true)
        @team.add_member(spammy_team_member)

        assert_performed_with(job: SubscribeAndNotifyJob) do
          create(:discussion_post, team: @team, user: spammy_team_member, body: "Spam!")
        end

        assert ActionMailer::Base.deliveries.empty?
      end
    end

    test "notifies computed subscribers via email on post creation" do
      another_team_member = create(:verified_user)
      @team.add_member(another_team_member)
      team_members = [@team_member, another_team_member]

      assert_performed_with(job: SubscribeAndNotifyJob) do
        post = create(:discussion_post, team: @team, body: "This is a new thing!")

        # Make sure an email was delivered to each subscriber.
        assert_equal team_members.size, ActionMailer::Base.deliveries.size

        # Make sure there is a summary
        refute_nil post.get_notification_summary.value

        ActionMailer::Base.deliveries.each do |mail|
          assert team_members.any? { |user| mail.smtp_envelope_to.include?(user.email) }
          assert_match(
            "[#{@team.name_with_owner}] #{post.title} (##{post.number})",
            mail.subject)
        end
      end
    end

    test "notification email contains correct Gmail ViewAction" do
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post, team: @team, body: "This is a new thing!")
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first

      assert_match("View this Discussion on GitHub", mail.encoded)
    end

    test "notification email contains unsubscribe link" do
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post, team: @team, body: "This is a new thing!")
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first

      assert_match(/unsubscribe<\/a>/, mail.encoded)
    end

    test "notifies computed subscribers via the web on post creation" do
      team_member = create(:verified_user)
      @team.add_member(team_member)

      enable_notifications_for_user(team_member, enabled_handlers: ["web"])

      web_notifications_interface = Newsies::Web.new
      assert_difference("web_notifications_interface.count(team_member)", 1) do
        assert_performed_with(job: SubscribeAndNotifyJob) do
          create(:discussion_post, team: @team, body: "This is a new thing!")
        end
      end
    end

    test "notifies computed subscribers of private post" do
      another_team_member = create(:verified_user)
      @team.add_member(another_team_member)
      team_members = [@team_member, another_team_member]

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post, team: @team, body: "This is a new thing!", private: true)
      end

      assert_equal team_members.size, ActionMailer::Base.deliveries.size
    end

    test "notifies mentionee with correct reason" do
      mentioned_user = create(:verified_user)
      @team.organization.add_member(mentioned_user)
      post = build(:discussion_post, team: @team, body: "Yo @#{mentioned_user.login}!")

      assert_notified_with_reason(
        post: post,
        notified_user: mentioned_user,
        reason_in_body: "you were mentioned",
        reason_in_header: "mention")
    end

    test "notifies team-mentionee with correct reason" do
      team_mentioned_user = create(:verified_user)
      mentioned_team = create(:team, organization: @team.organization, privacy: :closed)
      mentioned_team.add_member(team_mentioned_user)
      post = build(:discussion_post, team: @team, body: "Yo @#{mentioned_team.combined_slug}!")

      assert_notified_with_reason(
        post: post,
        notified_user: team_mentioned_user,
        reason_in_body: "you are on a team that was mentioned",
        reason_in_header: "team_mention")
    end

    test "notifies team member with correct reason" do
      team_member = create(:verified_user)
      @team.add_member(team_member)
      post = build(:discussion_post, team: @team)

      assert_notified_with_reason(
        post: post,
        notified_user: team_member,
        reason_in_body: "you are subscribed to this thread",
        reason_in_header: "subscribed")
    end

    test "does not send notifcations to subscribers from an org with disabled team discussions" do
      user = create(:verified_user)
      @team.add_member(user)

      @org.disallow_team_discussions(actor: @org.admin)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post, team: @team, body: "This is a new thing!")
      end

      assert_empty ActionMailer::Base.deliveries
    end

    test "does not notify team subscriber of private post that the subscriber cannot see" do
      GitHub.newsies.subscribe_to_list(@org_member, @team)
      team_subscription = GitHub.newsies.subscription_status(@org_member, @team)
      assert team_subscription.valid? && team_subscription.subscribed?

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post, team: @team, body: "This is a new thing!", private: true)
      end

      leaked_deliveries = ActionMailer::Base.deliveries.find_all do |mail|
        mail.destinations.include?(@org_member.email)
      end
      assert_empty leaked_deliveries
    end

    test "updates the notification summary when the post title changes" do
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
      @post = perform_enqueued_jobs(only: only) { create(:discussion_post, team: @team) }
      @post.title = "I'm Batman."
      perform_enqueued_jobs(only: [UpdateNotificationSummaryWithLocksJob]) do
        @post.save!
      end
      summary = NotificationSummary.by_thread(@team, @post)

      assert_equal "I'm Batman.", summary.reload.title
    end

    context "subscribing" do
      test "auto subscribes post author" do
        user = create(:verified_user)
        @team.add_member(user)

        assert_performed_with(job: SubscribeAndNotifyJob) do
          post = create(:discussion_post, user: user, team: @team)

          assert post.subscribed?(user),
            "user should be subscribed to post in Newsies after posting."
          assert_equal "author", post.subscription_status(user).reason
        end
      end

      test "auto subscribes mentioned users" do
        user = create(:verified_user)
        @post.team.add_member(user)
        refute @post.subscribed?(user)

        @post.body = "This is for your @#{user.login}"
        perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
          @post.save
        end

        assert @post.subscribed?(user),
          "user should be subscribed to post in Newsies after being mentioned."
        assert_equal "mention", @post.subscription_status(user).reason
      end

      test "auto subscribes members of mentioned teams" do
        team = create(:team, organization: @org)
        user = create(:verified_user)
        team.add_member(user)

        refute @post.subscribed?(user),
          "user should be subscribed to post in Newsies after their team is mentioned."

        @post.body = "This is for your @#{team.combined_slug}"
        perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
          @post.save
        end

        assert @post.subscribed?(user),
          "user should be subscribed to post in Newsies after their team is mentioned."
        assert_equal "team_mention", @post.subscription_status(user).reason
      end


      test "auto subscribes mentioned org admin to a private post" do
        org_admin = create(:verified_user)
        @org.add_admin(org_admin)
        @post.update!(private: true)
        refute @post.subscribed?(org_admin)

        @post.body = "Where you at @#{org_admin.login}?"
        assert_performed_with(job: UpdateSubscriptionsAndNotifyJob) do
          @post.save
        end

        assert @post.subscribed?(org_admin)
        assert_equal "mention", @post.subscription_status(org_admin).reason
      end

      test "auto subscribes team-mentioned org admin to a private post" do
        org_admin = create(:verified_user)
        @org.add_admin(org_admin)
        other_team = create(:team, organization: @org, privacy: :closed)
        other_team.add_member(org_admin)
        @post.update!(private: true)
        refute @post.subscribed?(org_admin)

        @post.body = "Thoughts @#{other_team.combined_slug}?"
        assert_performed_with(job: UpdateSubscriptionsAndNotifyJob) do
          @post.save
        end

        assert @post.subscribed?(org_admin)
        assert_equal "team_mention", @post.subscription_status(org_admin).reason
      end

      test "does not subscribe mentioned user to a private post the user cannot see" do
        mentioned_user = create(:verified_user)
        @org.add_member(mentioned_user)
        @post.update!(private: true)
        refute Platform::Authorization::Permission.new(viewer: mentioned_user, origin: Platform::ORIGIN_MANUAL_EXECUTION).typed_can_see?("TeamDiscussion", @post).sync

        @post.body = "Where you at @#{mentioned_user.login}?"
        assert_performed_with(job: UpdateSubscriptionsAndNotifyJob) do
          @post.save
        end

        refute @post.subscribed?(mentioned_user)
      end

      test "does not subscribe member of mentioned team to a private post the user cannot see" do
        mentioned_team = create(:team, organization: @org)
        mentioned_team_member = create(:verified_user)
        mentioned_team.add_member(mentioned_team_member)
        @post.update!(private: true)
        refute Platform::Authorization::Permission.new(viewer: mentioned_team_member, origin: Platform::ORIGIN_MANUAL_EXECUTION).typed_can_see?("TeamDiscussion", @post).sync

        @post.body = "Where's @#{mentioned_team.combined_slug}?"
        assert_performed_with(job: UpdateSubscriptionsAndNotifyJob) do
          @post.save
        end

        refute @post.subscribed?(mentioned_team_member)
      end
    end
  end

  context "reactions" do
    test "the author can react to it" do
      reaction = Reaction.react(
        user: @post.user,
        subject_id: @post.id,
        subject_type: @post.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "a team member can react to it" do
      teammate = create(:verified_user)
      @team.add_member(teammate)

      reaction = Reaction.react(
        user: teammate,
        subject_id: @post.id,
        subject_type: @post.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "an org admin can react to it" do
      admin = create(:verified_user)
      @org.add_admin(admin)

      reaction = Reaction.react(
        user: admin,
        subject_id: @post.id,
        subject_type: @post.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "an arbitrary user cannot react to it" do
      reaction = Reaction.react(
        user: create(:verified_user),
        subject_id: @post.id,
        subject_type: @post.class.name,
        content: "+1")

      refute reaction.valid?
      refute reaction.persisted?
    end
  end

  context "#async_viewer_can_pin?" do
    test "author can pin" do
      assert @post.async_viewer_can_pin?(@post.user).sync
    end

    test "direct team member can pin" do
      team_member = create(:verified_user)
      @post.team.add_member(team_member)

      assert @post.async_viewer_can_pin?(team_member).sync
    end

    test "nested team member can pin" do
      nested_team_member = create(:verified_user)
      @post.team.update!(privacy: :closed)
      child_team = create(:team, organization: @org, parent_team_id: @post.team_id, privacy: :closed)
      child_team.add_member(nested_team_member)

      assert @post.async_viewer_can_pin?(nested_team_member).sync
    end

    test "org admin can pin" do
      org_admin = create(:verified_user)
      @post.team.organization.add_admin(org_admin)

      assert @post.async_viewer_can_pin?(org_admin).sync
    end

    test "non-admin org member cannot pin" do
      @post.team.update!(privacy: :closed)
      org_member = create(:verified_user)
      @org.add_member(org_member)

      refute @post.async_viewer_can_pin?(org_member).sync
    end

    test "resolves efficiently when called multiple times across posts for the same team" do
      posts = [@post] + 2.times.map { create(:discussion_post, team: @post.team) }
      team_member = create(:verified_user)
      @post.team.add_member(team_member)

      num_queries = count_queries do
        Promise.all(posts.map { |p| p.async_viewer_can_pin?(team_member) }).sync
      end

      # Team members can pin purely by virtue of their membership to the team. So, for three posts
      # on the same team, make sure that we only query for team membership once in order to resolve
      # all promises.
      assert(
        num_queries < 2,
        "should not have queried #{num_queries} to resolve all async_viewer_can_pin? promises")
    end
  end

  context "#async_readable_by?" do
    test "resolves to false if the viewer is nil" do
      refute @post.async_readable_by?(nil).sync
    end

    test "resolves to false if the viewer cannot access the team" do
      refute @post.async_readable_by?(create(:verified_user)).sync
    end

    test "resolves to true if the post is public" do
      @post.update!(private: false)
      assert @post.public?

      assert @post.async_readable_by?(@org_member).sync
    end

    test "resolves to true if the viewer ID has been preloaded" do
      @post.update!(private: true)
      assert @post.private?

      # We need to check if team discussions are enabled at all for
      # the org, but the preloaded ID should short-circuit all other queries.
      count = count_queries { @org.async_team_discussions_allowed?.sync }
      assert_query_count(count) do
        assert @post
          .async_readable_by?(@team_member, preloaded_team_member_ids: [@team_member.id])
          .sync
      end
    end

    test "resolves to true if post is private but the viewer is an org admin" do
      @post.update!(private: true)
      assert @post.private?

      assert @post.async_readable_by?(@org.admin).sync
    end

    test "resolves to true if the post is private but the viewer is a team member" do
      @post.update!(private: true)
      assert @post.private?
      assert Team.member_of?(@team.id, @team_member.id, immediate_only: true)

      assert @post.async_readable_by?(@team_member).sync
    end

    test "resolves to true if the post is private but the viewer is a nested team member" do
      nested_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
      nested_team_member = create(:verified_user)
      nested_team.add_member(nested_team_member)
      @post.update!(private: true)
      assert @post.private?
      assert Team.member_of?(@team.id, nested_team_member.id, immediate_only: false)

      assert @post.async_readable_by?(nested_team_member).sync
    end

    test "resolves to false if the post is private and the viewer is not a team member" do
      @post.update!(private: true)
      assert @post.private?
      refute Team.member_of?(@team.id, @org_member.id, immediate_only: false)

      refute @post.async_readable_by?(@org_member).sync
    end

    test "resolves to true if the viewer is a bot with the `team_discussions` permission" do
      assert @post.async_readable_by?(@installation_with_read_permission.bot).sync
    end

    test "resolves to false if the viewer is a bot without the `team_discussions` permission" do
      refute @post.async_readable_by?(@random_installation.bot).sync
    end

    test "resolves to false if discussions are disabled on the org" do
      @org.disallow_team_discussions(actor: @org.admin)

      refute @post.async_readable_by?(@org_member).sync
    end
  end

  context "#organization_id" do
    test "returns the ID of the team discussion's team's organization" do
      assert_equal @org.id, @post.organization_id
    end
  end

  context "#destroy" do
    test "deletes the post's replies" do
      create(:discussion_post_reply, discussion_post: @post)

      only = [DestroyDependentRecordsJob, Newsies::DeleteAllForThreadJob]
      perform_enqueued_jobs(only: only) do
        assert_difference("DiscussionPostReply.count", -1) do
          @post.destroy
        end
      end
    end

    test "deletes the post's reactions" do
      Reaction.react(
        user: @post.user,
        subject_id: @post.id,
        subject_type: "DiscussionPost",
        content: "+1",
      )

      only = [DestroyDependentRecordsJob, Newsies::DeleteAllForThreadJob]
      perform_enqueued_jobs(only: only) do
        assert_difference("Reaction.count", -1) do
          @post.destroy
        end
      end
    end

    test "deletes the reactions of the post's replies" do
      comment = create(:discussion_post_reply, discussion_post: @post)
      Reaction.react(
        user: @post.user,
        subject_id: comment.id,
        subject_type: "DiscussionPostReply",
        content: "+1",
      )

      only = [DestroyDependentRecordsJob, Newsies::DeleteAllForThreadJob]
      perform_enqueued_jobs(only: only) do
        assert_difference("Reaction.count", -1) do
          @post.destroy
        end
      end
    end

    test "deletes the post's subscriptions" do

      post_subscribers = 2.times.map { create(:verified_user) }
      post_subscribers.each do |s|
        GitHub.newsies.subscribe_to_thread(s, @post.team, @post, "manual")
      end
      assert_equal(
        3, # Two subscribers created above, and the post's author.
        GitHub
          .newsies
          .subscriber_set_for(list: @post.team, thread: @post)
          .subscribed
          .count { |(_, s)| s.reason != "list" })

      perform_enqueued_jobs(only: [Newsies::DeleteAllForThreadJob]) { @post.destroy }

      assert_equal(
        0,
        GitHub
          .newsies
          .subscriber_set_for(list: @post.team, thread: @post)
          .subscribed
          .count { |(_, s)| s.reason != "list" })
    end

    test "cleans up newsies data for thread when discussion post is destroyed" do
      post = create(:discussion_post, team: @team)

      GitHub.newsies.expects(:async_delete_all_for_thread).with(@team, post)
      post.destroy
    end

    test "updates the notfication indicator" do
      enable_notifications_for_user(@team_member, enabled_handlers: ["web"])

      perform_enqueued_jobs(only: [Newsies::DeleteAllForThreadJob]) do
        only = [Newsies::DeliverNotificationsJob]
        post = perform_enqueued_jobs(only: only) do
          only = [Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob, SubscribeAndNotifyJob]
          perform_enqueued_jobs(only: only) { create(:discussion_post, team: @team) }
        end

        assert_equal :global, @team_member.indicator_mode

        post.destroy

        member = User.find_by_id(@team_member.id)
        assert_equal :none, member.indicator_mode
      end
    end
  end

  context "audit logging" do

    test "creates an audit log entry on successful update" do
      events = subscribe("discussion_post.update")
      old_body = @post.body
      old_title = @post.title
      now = Time.now
      pinned_by_user = create(:verified_user)

      @post.update!(
        body: "My updated text!",
        title: "My new title!",
        pinned_at: now,
        pinned_by_user_id: pinned_by_user.id)
      update_event = events.pop

      pinned_at = update_event.payload.extract! :pinned_at

      assert update_event
      assert_equal("discussion_post.update", update_event.name)
      assert_equal(
        {
          body: @post.body,
          number: @post.number,
          old_body: old_body,
          old_title: old_title,
          old_pinned_at: nil,
          old_pinned_by_user: nil,
          pinned_by_user: pinned_by_user.login,
          pinned_by_user_id: pinned_by_user.id,
          private: false,
          team: @post.team.to_s,
          team_id: @post.team.id,
          title: @post.title,
          updated_at: @post.updated_at,
          user: @post.user.login,
          user_id: @post.user_id,
          org: @org.to_s,
          org_id: @org.id,
        },
        update_event.payload,
      )
      assert_same_time now, @post.pinned_at
    end

    test "does not create audit log entry when skipping update instrumentation" do
      events = subscribe("discussion_post.update")
      @post.skip_instrument_update = true

      @post.update!(body: "My updated text!")
      update_event = events.pop

      refute update_event
    end

    test "creates an audit log entry on successful deletion" do
      events = subscribe("discussion_post.destroy")

      @post.destroy
      refute DiscussionPost.exists?(@post.id)
      destroy_event = events.pop

      assert destroy_event
      assert_equal("discussion_post.destroy", destroy_event.name)
      assert_equal(
        {
          body: @post.body,
          number: @post.number,
          pinned_at: nil,
          pinned_by_user: nil,
          private: false,
          team: @post.team.to_s,
          team_id: @post.team.id,
          title: @post.title,
          updated_at: @post.updated_at,
          user: @post.user.login,
          user_id: @post.user_id,
          org: @org.to_s,
          org_id: @org.id,
        },
        destroy_event.payload)
    end
  end

  context "async_viewer_can_update?" do
    test "resolves to true for the discussion's author" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      assert discussion.async_viewer_can_update?(discussion.user).sync
    end

    test "resolves to true for a team admin" do
      @team.promote_maintainer(@team_member)
      team_admin = @team_member
      assert @post.user != team_admin

      assert @post.async_viewer_can_update?(team_admin).sync
    end

    test "resolves to true for an org admin" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      assert discussion.user != @org.admin

      assert discussion.async_viewer_can_update?(@org.admin).sync
    end

    test "resolves to true for a team member" do
      assert @post.user != @team_member
      assert @post.async_viewer_can_update?(@team_member).sync
    end

    test "resolves to true for an org member" do
      org_member = create(:verified_user)
      @org.add_member(org_member)

      assert @post.async_viewer_can_update?(org_member).sync
    end

    test "resolves to false for author who can no longer see the discussion" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @team.organization.remove_member(discussion.user) }
      refute @team.organization.direct_or_team_member?(discussion.user)

      refute discussion.async_viewer_can_update?(discussion.user).sync
    end

    test "resolves to true for a bot with write permission" do
      assert @post.async_viewer_can_update?(@installation_with_write_permission.bot).sync
    end

    test "resolves to false for a bot without write permission" do
      refute @post.async_viewer_can_update?(@installation_with_read_permission.bot).sync
    end
  end

  context "async_viewer_can_delete?" do
    test "resolves to true for the discussion's author" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      assert discussion.async_viewer_can_delete?(discussion.user).sync
    end

    test "resolves to true for a team admin" do
      @team.promote_maintainer(@team_member)
      team_admin = @team_member
      assert @post.user != team_admin

      assert @post.async_viewer_can_delete?(team_admin).sync
    end

    test "resolves to true for an org admin" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      assert discussion.user != @org.admin

      assert discussion.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to true on ghost user posts" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      discussion.user.destroy
      discussion.reload

      assert discussion.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to false for a team member" do
      assert @post.user != @team_member
      refute @post.async_viewer_can_delete?(@team_member).sync
    end

    test "resolves to false for an org member" do
      org_member = create(:verified_user)
      @org.add_member(org_member)

      refute @post.async_viewer_can_delete?(org_member).sync
    end

    test "resolves to false for author who can no longer see the discussion" do
      discussion = create(:discussion_post, team: @team, user: @team_member)
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @team.organization.remove_member(discussion.user) }
      refute @team.organization.direct_or_team_member?(discussion.user)

      refute discussion.async_viewer_can_delete?(discussion.user).sync
    end

    test "resolves to false for a bot with write permission who is not author" do
      assert @post.user != @installation_with_write_permission.bot
      refute @post
        .async_viewer_can_delete?(@installation_with_write_permission.bot)
        .sync
    end

    test "resolves to true for a bot with write permission who is also the author" do
      discussion = create(:discussion_post, team: @team, user: @installation_with_write_permission.bot)
      assert discussion
        .async_viewer_can_delete?(@installation_with_write_permission.bot)
        .sync
    end

    test "resolves to false for a bot without write permission" do
      refute @post.async_viewer_can_delete?(@installation_with_read_permission.bot).sync
    end
  end

  [:title, :body].each do |field|
    test "supports emoji for #{field}" do
      post = create(:discussion_post, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(post, field)
    end
  end

  private

  def assert_notified_with_reason(post:, notified_user:, reason_in_body:, reason_in_header:)
    assert_performed_with(job: SubscribeAndNotifyJob) do
      post.save!

      full_reason = "because #{reason_in_body}"
      matching_notification = ActionMailer::Base.deliveries.any? do |mail|
        correct_recipient = mail.smtp_envelope_to.include?(notified_user.email)
        correct_reason_in_body = mail.encoded =~ /#{full_reason}/
        correct_reason_in_header = mail.header["X-GitHub-Reason"].to_s == reason_in_header

        correct_recipient && correct_reason_in_body && correct_reason_in_header
      end

      assert(
        matching_notification,
        "#{notified_user.email} should have been notified with reason \"#{full_reason}\"")
    end
  end
end
