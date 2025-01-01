# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDiscussionPostReplyTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)

    @org_members = 2.times.map { create(:user) }
    @org_members.each { |u| @org.add_member(u) }

    @post = create(:organization_discussion_post, organization: @org, private: true,
                   body: "This is a post!", user: @org_members.first)
    @reply = create(:organization_discussion_post_reply, discussion_post: @post,
                    user: @org_members.second)

    @public_post = create(:organization_discussion_post, organization: @org, private: false,
                   body: "This is another post!", user: @org_members.second)
    @public_reply = create(:organization_discussion_post_reply, discussion_post: @public_post,
                           user: @org_members.first)
  end

  context "validations" do
    test "requires non-empty body" do
      reply = build(:organization_discussion_post_reply, body: "", discussion_post: @post)
      refute_predicate reply, :valid?
      assert_equal "Body cannot be blank", reply.errors.full_messages.to_sentence
    end

    test "requires body that is more than just whitespace" do
      reply = build(:organization_discussion_post_reply, body: "   ", discussion_post: @post)
      refute_predicate reply, :valid?
      assert_equal "Body cannot be blank", reply.errors.full_messages.to_sentence
    end
  end

  test "generates a unique sequence for each post" do
    post = create(:organization_discussion_post)
    reply1 = post.replies.create(body: "a reply", user: @org_members.first)
    reply2 = post.replies.create(body: "reply 2", user: @org_members.first)
    reply_other = create(:organization_discussion_post_reply,
      body: "reply to a different post",
      user: @org_members.first)

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

  context "async_viewer_can_update?" do
    test "resolves to true for the reply's author" do
      assert @reply.async_viewer_can_update?(@reply.user).sync
    end

    test "resolves to true for an org admin" do
      org_admin = create(:user)
      @org.add_admin(org_admin)

      assert @reply.async_viewer_can_update?(org_admin).sync
    end

    test "resolves to false for an org member" do
      assert @reply.user != @org_members.first
      refute @reply.async_viewer_can_update?(@org_members.first).sync
    end

    test "resolves to false for author who can no longer see the comment" do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @reply.organization.remove_member(@reply.user)
      end
      refute @reply.organization.direct_or_team_member?(@reply.user)

      refute @reply.async_viewer_can_update?(@reply.user).sync
    end
  end

  context "async_viewer_can_delete?" do
    test "resolves to true for the reply's author" do
      assert @reply.async_viewer_can_delete?(@reply.user).sync
    end

    test "resolves to true for an org admin" do
      assert @reply.user != @org.admin
      assert @reply.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to true on a ghost user's reply for org admin" do
      @reply.user.destroy
      @reply.reload
      assert @reply.async_viewer_can_delete?(@org.admin).sync
    end

    test "resolves to false for an org member" do
      refute_equal @reply.user, @org_members.first
      refute @reply.async_viewer_can_delete?(@org_members.first).sync
    end

    test "resolves to false for author who can no longer see the comment" do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @reply.organization.remove_member(@reply.user)
      end
      refute @reply.organization.direct_or_team_member?(@reply.user)

      refute @reply.async_viewer_can_delete?(@reply.user).sync
    end
  end
end
