# typed: false
# frozen_string_literal: true
require "test_helper"

class DiscussionPostReplyTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @org_admin = create(:verified_user)
    @org = create(:organization, admin: @org_admin)
    @team = create(:team, organization: @org, privacy: :closed)

    @team_members = 2.times.map { create(:verified_user) }
    @team_members.each { |u| @team.add_member(u) }

    @post = create(:discussion_post, team: @team, body: "This is a post!", user: @team_members.first)
    @reply = create(:discussion_post_reply, discussion_post: @post, user: @team_members.second)
  end

  setup { ActionMailer::Base.deliveries.clear }

  context "validations" do
    test "requires non-empty body" do
      reply = build(:discussion_post_reply, body: "", discussion_post: @post)
      refute reply.valid?
      assert_equal "Body cannot be blank", reply.errors.full_messages.to_sentence
    end

    test "requires body that is more than just whitespace" do
      reply = build(:discussion_post_reply, body: "   ", discussion_post: @post)
      refute reply.valid?
      assert_equal "Body cannot be blank", reply.errors.full_messages.to_sentence
    end
  end

  test "generates a unique sequence for each post" do
    post = create(:discussion_post)
    reply1 = post.replies.create(body: "a reply", user: @team_members.first)
    reply2 = post.replies.create(body: "reply 2", user: @team_members.first)
    reply_other = create(:discussion_post_reply,
      body: "reply to a different post",
      user: @team_members.first)

    assert_equal 1, reply1.number
    assert_equal 2, reply2.number
    assert_equal 1, reply_other.number
  end

  test "number cannot be changed for existing replies" do
    assert_equal 1, @reply.number

    @reply.number = 5
    @reply.save

    assert_equal 1, @reply.reload.number
  end

  context "reactions" do
    test "the author can react to it" do
      reaction = Reaction.react(
        user: @reply.user,
        subject_id: @reply.id,
        subject_type: @reply.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "a team member can react to it" do
      reaction = Reaction.react(
        user: @team_members.first,
        subject_id: @reply.id,
        subject_type: @reply.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "an org admin can react to it" do
      admin = create(:verified_user)
      @org.add_admin(admin)

      reaction = Reaction.react(
        user: admin,
        subject_id: @reply.id,
        subject_type: @reply.class.name,
        content: "+1")

      assert reaction.persisted?
    end

    test "an arbitrary user cannot react to it" do
      reaction = Reaction.react(
        user: create(:verified_user),
        subject_id: @reply.id,
        subject_type: @reply.class.name,
        content: "+1")

      refute reaction.valid?
      refute reaction.persisted?
    end
  end

  context "websocket" do
    test "triggers websocket message on create" do
      Timecop.freeze do
        channel = GitHub::WebSocket::Channels.discussion_post(@post)

        data = {
          timestamp: Time.now.to_i,
          reason:    "discussion post ##{@post.id} updated",
          wait:      @post.default_live_updates_wait,
        }

        GitHub::WebSocket.stubs(:notify_discussion_post_channel)
        GitHub::WebSocket.expects(:notify_discussion_post_channel)
          .with(@post, channel, data)
          .returns([]).once
        create(:discussion_post_reply,
          discussion_post: @post,
          user_id: @team_members.first.id)
      end
    end
  end

  context "notifications" do
    if GitHub.spamminess_check_enabled?
      test "does not notify anyone for reply creation by spammy user" do
        spammer = create(:user, spammy: true)
        @team.add_member(spammer)

        assert_performed_with(job: SubscribeAndNotifyJob) do
          create(:discussion_post_reply, discussion_post: @post, user: spammer, body: "Spam!")
        end

        assert ActionMailer::Base.deliveries.empty?
      end
    end

    test "notifies subscribers via email on reply creation" do
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
      end

      # Make sure an email was delivered to each subscriber.
      assert_equal 2, ActionMailer::Base.deliveries.size

      ActionMailer::Base.deliveries.each do |mail|
        assert @team_members.any? { |user| mail.smtp_envelope_to.include?(user.email) }
        expected_subject = "Re: [#{@team.name_with_owner}] #{@post.title} (##{@post.number})"
        assert_match(expected_subject, mail.subject)
      end
    end

    test "notification email contains correct Gmail ViewAction" do
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
      end

      # Make sure an email was delivered to each subscriber.
      assert_equal 2, ActionMailer::Base.deliveries.size

      ActionMailer::Base.deliveries.each do |mail|
        assert_match("View this Discussion on GitHub", mail.encoded)
      end
    end

    test "notification email contains unsubscribe link" do
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
      end

      # Make sure an email was delivered to each subscriber.
      assert_equal 2, ActionMailer::Base.deliveries.size

      ActionMailer::Base.deliveries.each do |mail|
        assert_match(/unsubscribe<\/a>/, mail.encoded)
      end
    end

    test "notifies subscribers via web on reply creation" do
      @team_members.each do |member|
        enable_notifications_for_user(member, enabled_handlers: ["web"])
      end

      web_notifications_interface = Newsies::Web.new
      assert_difference("web_notifications_interface.count(@team_members[0])", 1) do
        assert_difference("web_notifications_interface.count(@team_members[1])", 1) do
          assert_performed_with(job: SubscribeAndNotifyJob) do
            create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
          end
        end
      end
    end

    test "notifies subscribers for reply to private post" do
      @post.update!(private: true)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
      end

      assert_equal 2, ActionMailer::Base.deliveries.size
    end

    test "notifies parent post author with correct reason" do
      new_post = nil
      assert_performed_with(job: SubscribeAndNotifyJob) do
        new_post = create(:discussion_post, team: @team, user: @post.user)
      end

      reply = build(:discussion_post_reply, discussion_post: new_post)

      assert_notified_with_reason(
        reply: reply,
        notified_user: new_post.user,
        reason_in_body: "you authored the thread",
        reason_in_header: "author")
    end

    test "notifies previous commenter with correct reason" do
      previous_commenter = create(:verified_user)
      @team.add_member(previous_commenter)
      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, user: previous_commenter)
      end
      reply = build(:discussion_post_reply, discussion_post: @post)

      assert_notified_with_reason(
        reply: reply,
        notified_user: previous_commenter,
        reason_in_body: "you commented",
        reason_in_header: "comment")
    end

    test "notifies mentionee with correct reason" do
      mentioned_user = create(:verified_user)
      @team.organization.add_member(mentioned_user)
      reply = build(:discussion_post_reply,
        discussion_post: @post,
        body: "Yo @#{mentioned_user.login}!")

      assert_notified_with_reason(
        reply: reply,
        notified_user: mentioned_user,
        reason_in_body: "you were mentioned",
        reason_in_header: "mention")
    end

    test "notifies team-mentionee with correct reason" do
      team_mentioned_user = create(:verified_user)
      mentioned_team = create(:team, organization: @team.organization, privacy: :closed)
      mentioned_team.add_member(team_mentioned_user)
      reply = build(:discussion_post_reply,
        discussion_post: @post,
        body: "Yo @#{mentioned_team.combined_slug}!")

      assert_notified_with_reason(
        reply: reply,
        notified_user: team_mentioned_user,
        reason_in_body: "you are on a team that was mentioned",
        reason_in_header: "team_mention")
    end

    test "notifies team member with correct reason" do
      team_member = create(:verified_user)
      @team.add_member(team_member)
      reply = build(:discussion_post_reply, discussion_post: @post)

      assert_notified_with_reason(
        reply: reply,
        notified_user: team_member,
        reason_in_body: "you are subscribed to this thread",
        reason_in_header: "subscribed")
    end

    test "does not send notifcations to subscribers from an org with disabled team discussions" do
      user = create(:verified_user)
      @team.add_member(user)
      post = create(:discussion_post, team: @team, body: "This is a post!", user: @team_members.first)

      ActionMailer::Base.deliveries.clear

      @org.disallow_team_discussions(actor: @org_admin)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: post, body: "This is a reply.")

        assert_empty ActionMailer::Base.deliveries
      end
    end

    test "does not notify team subscriber of reply to private post that subscriber cannot see" do
      @post.update!(private: true)
      team_subscriber = create(:verified_user)
      @org.add_member(team_subscriber)
      GitHub.newsies.subscribe_to_list(team_subscriber, @team)
      team_subscription = GitHub.newsies.subscription_status(team_subscriber, @team)
      assert team_subscription.valid? && team_subscription.subscribed?

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "This is a reply.")
      end

      leaked_deliveries = ActionMailer::Base.deliveries.find_all do |mail|
        mail.destinations.include?(team_subscriber.email)
      end
      assert_empty leaked_deliveries
    end

    test "subscribes the author of a reply to its post" do
      user = create(:verified_user)
      @team.add_member(user)

      refute @post.subscribed?(user)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, user: user)
      end

      assert @post.subscribed?(user)
      assert_equal "comment", @post.subscription_status(user).reason
    end

    test "subscribes users mentioned in a reply to its post" do
      user = create(:verified_user)
      @team.add_member(user)
      refute @post.subscribed?(user)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "Check this out @#{user.login}!")
      end

      assert @post.subscribed?(user)
      assert_equal "mention", @post.subscription_status(user).reason
    end

    test "subscribes members of teams mentioned in a reply to its post" do
      team = create(:team, organization: @org)
      user = create(:verified_user)
      team.add_member(user)
      refute @post.subscribed?(user)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "Check this out @#{team.combined_slug}!")
      end

      assert @post.subscribed?(user)
      assert_equal "team_mention", @post.subscription_status(user).reason
    end

    test "auto subscribes mentioned org admin to a private post" do
      @post.update!(private: true)
      refute @post.subscribed?(@org_admin)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "Check it @#{@org_admin.login}!")
      end

      assert @post.subscribed?(@org_admin)
      assert_equal "mention", @post.subscription_status(@org_admin).reason
    end

    test "auto subscribes team-mentioned org admin to a private post" do
      mentioned_team = create(:team, organization: @org, privacy: :closed)
      mentioned_team.add_member(@org_admin)
      @post.update!(private: true)
      refute @post.subscribed?(@org_admin)

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply,
          discussion_post: @post,
          body: "Thoughts @#{mentioned_team.combined_slug}?")
      end

      assert @post.subscribed?(@org_admin)
      assert_equal "team_mention", @post.subscription_status(@org_admin).reason
    end

    test "does not subscribe mentioned user to a private post the user cannot see" do
      mentioned_user = create(:verified_user)
      @org.add_member(mentioned_user)
      @post.update!(private: true)
      refute Platform::Authorization::Permission.new(viewer: mentioned_user, origin: Platform::ORIGIN_MANUAL_EXECUTION).typed_can_see?("TeamDiscussion", @post).sync

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply, discussion_post: @post, body: "Where you at @#{mentioned_user}?")
      end

      refute @post.subscribed?(mentioned_user)
    end

    test "does not subscribe member of mentioned team to a private post the user cannot see" do
      mentioned_team = create(:team, organization: @org)
      mentioned_team_member = create(:verified_user)
      mentioned_team.add_member(mentioned_team_member)
      @post.update!(private: true)
      refute Platform::Authorization::Permission.new(viewer: mentioned_team_member, origin: Platform::ORIGIN_MANUAL_EXECUTION).typed_can_see?("TeamDiscussion", @post).sync

      assert_performed_with(job: SubscribeAndNotifyJob) do
        create(:discussion_post_reply,
          discussion_post: @post,
          body: "Where's @#{mentioned_team.combined_slug}?")
      end

      refute @post.subscribed?(mentioned_team_member)
    end
  end

  context "#destroy" do
    test "deletes the reactions of the post's replies" do
      Reaction.react(
        user: @reply.user,
        subject_id: @reply.id,
        subject_type: "DiscussionPostReply",
        content: "+1",
      )

      assert_difference("Reaction.count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @reply.destroy }
      end
    end
  end

  context "audit logging" do
    test "creates an audit log entry on successful update" do
      events = subscribe("discussion_post_reply.update")
      old_body = @reply.body

      @reply.update!(body: "My updated text")
      update_event = events.pop

      assert update_event
      assert_equal("discussion_post_reply.update", update_event.name)
      assert_equal(
        {
          body: @reply.body,
          discussion_post_id: @reply.discussion_post_id,
          discussion_post_number: @reply.discussion_post.number,
          number: @reply.number,
          old_body: old_body,
          org: @org.to_s,
          org_id: @org.id,
          team: @reply.team.to_s,
          team_id: @reply.team.id,
          updated_at: @reply.updated_at,
          user: @reply.user.login,
          user_id: @reply.user_id,
        },
        update_event.payload)
    end

    test "creates an audit log entry on successful deletion" do
      events = subscribe("discussion_post_reply.destroy")

      @reply.destroy
      refute DiscussionPostReply.exists?(@reply.id)
      destroy_event = events.pop

      assert destroy_event
      assert_equal("discussion_post_reply.destroy", destroy_event.name)
      assert_equal(
        {
          body: @reply.body,
          discussion_post_id: @reply.discussion_post_id,
          discussion_post_number: @reply.discussion_post.number,
          number: @reply.number,
          org: @org.to_s,
          org_id: @org.id,
          team: @reply.team.to_s,
          team_id: @reply.team.id,
          updated_at: @reply.updated_at,
          user: @reply.user.login,
          user_id: @reply.user_id,
        },
        destroy_event.payload)
    end
  end

  context "async_readable_by?" do
    test "resolves to false if discussions are disabled on the org" do
      @org.disallow_team_discussions(actor: @org.admin)

      refute @reply.async_readable_by?(@team_members.first).sync
    end
  end

  context "async_viewer_can_update?" do
    test "resolves to true for the reply's author" do
      assert @reply.async_viewer_can_update?(@reply.user).sync
    end

    test "resolves to true for a team admin" do
      @team.promote_maintainer(@team_members.first)
      team_admin = @team_members.first
      assert @reply.user != team_admin

      assert @reply.async_viewer_can_update?(team_admin).sync
    end

    test "resolves to true for an org admin" do
      assert @reply.user != @org.admin
      assert @reply.async_viewer_can_update?(@org.admin).sync
    end

    test "resolves to true for a team member" do
      assert @reply.user != @team_members.first
      assert @reply.async_viewer_can_update?(@team_members.first).sync
    end

    test "resolves to true for an org member" do
      org_member = create(:verified_user)
      @org.add_member(org_member)

      assert @reply.async_viewer_can_update?(org_member).sync
    end

    test "resolves to false for author who can no longer see the comment" do
      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        @reply.team.organization.remove_member!(@reply.user)
      end
      refute @reply.team.organization.direct_or_team_member?(@reply.user)

      refute @reply.async_viewer_can_update?(@reply.user).sync
    end

    test "resolves to true for a bot with write permission" do
      installation = make_integration_installation(target: @org,
        name: "accessible-bot", permissions: { team_discussions: :write })

      assert @reply.async_viewer_can_update?(installation.bot).sync
    end

    test "resolves to false for a bot without write permission" do
      installation = make_integration_installation(target: @org,
        name: "inaccessible-bot", permissions: { team_discussions: :read })

      refute @reply.async_viewer_can_update?(installation.bot).sync
    end
  end

  context "async_viewer_can_delete?" do
    test "resolves to true for the reply's author" do
      assert @reply.async_viewer_can_delete?(@reply.user).sync
    end

    test "resolves to true for a team admin" do
      @team.promote_maintainer(@team_members.first)
      team_admin = @team_members.first
      assert @reply.user != team_admin

      assert @reply.async_viewer_can_delete?(team_admin).sync
    end

    test "resolves to true for an org admin" do
      assert @reply.user != @org.admin
      assert @reply.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to true on a ghost user's reply" do
      @reply.user.destroy
      @reply.reload
      assert @reply.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to false for a team member" do
      assert @reply.user != @team_members.first
      refute @reply.async_viewer_can_delete?(@team_members.first).sync
    end

    test "resolves to false for an org member" do
      org_member = create(:verified_user)
      @org.add_member(org_member)

      refute @reply.async_viewer_can_delete?(org_member).sync
    end

    test "resolves to false for author who can no longer see the comment" do
      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        @reply.team.organization.remove_member!(@reply.user)
      end
      refute @reply.team.organization.direct_or_team_member?(@reply.user)

      refute @reply.async_viewer_can_delete?(@reply.user).sync
    end

    test "resolves to true for a bot with write permission who is also the author" do
      installation = make_integration_installation(target: @org,
        name: "accessible-bot", permissions: { team_discussions: :write })
      reply = create(:discussion_post_reply, discussion_post: @post, user: installation.bot)

      assert reply.async_viewer_can_delete?(installation.bot).sync
    end

    test "resolves to false for a bot with write permission who is not the author" do
      installation = make_integration_installation(target: @org,
        name: "accessible-bot", permissions: { team_discussions: :write })

      refute @reply.async_viewer_can_delete?(installation.bot).sync
    end

    test "resolves to false for a bot without write permission" do
      installation = make_integration_installation(target: @org,
        name: "inaccessible-bot", permissions: { team_discussions: :read })

      refute @reply.async_viewer_can_delete?(installation.bot).sync
    end
  end

  private

  def assert_notified_with_reason(reply:, notified_user:, reason_in_body:, reason_in_header:)
    assert_performed_with(job: SubscribeAndNotifyJob) do
      reply.save!

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
