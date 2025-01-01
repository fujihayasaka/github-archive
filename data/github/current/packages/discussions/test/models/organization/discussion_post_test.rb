# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDiscussionPostTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @org = create(:organization)

    @org_member = create(:user)
    @org.add_member(@org_member)

    @post = create(:organization_discussion_post, organization: @org, private: true)
    @public_post = create(:organization_discussion_post, organization: @org, private: false)
  end

  context "visible_to scope" do
    test "includes only public posts for anonymous viewer" do
      result = OrganizationDiscussionPost.visible_to(nil)

      assert_includes result, @public_post
      refute_includes result, @post
      assert result.all?(&:public?)
    end

    test "includes private posts for org viewer belongs to" do
      other_org = create(:organization)
      other_post = create(:organization_discussion_post, organization: other_org, private: true)
      other_public_post = create(:organization_discussion_post, organization: other_org,
                                 private: false)

      result = OrganizationDiscussionPost.visible_to(@org_member)

      assert_includes result, @post
      assert_includes result, @public_post
      refute_includes result, other_post
      assert_includes result, other_public_post
    end
  end

  context "validations" do
    test "requires non-empty body" do
      post = build(:organization_discussion_post, body: "")
      refute post.valid?
      assert_equal "Body cannot be blank", post.errors.full_messages.to_sentence
    end

    test "requires body that is more than just whitespace" do
      post = build(:organization_discussion_post, body: "   ")
      refute post.valid?
      assert_equal "Body cannot be blank", post.errors.full_messages.to_sentence
    end

    test "limits title to 256 characters (1024 bytes/4)" do
      title = "a" * (OrganizationDiscussionPost::TITLE_BYTESIZE_LIMIT + 1)
      post = build(:organization_discussion_post, title: title)
      refute post.valid?
      assert_equal "Title is too long (maximum is 256 characters)",
        post.errors.full_messages.to_sentence
    end
  end

  context "human-readable sequence numbers" do
    test "receives the first sequence number as the first post for the org" do
      assert_equal 1, @post[:number]
    end

    test "receives the next sequence number when there are existing posts for the org" do
      org = create(:organization)
      2.times { create(:organization_discussion_post, organization: org) }
      assert_equal 3, create(:organization_discussion_post, organization: org)[:number]
    end

    test "does not reuse sequence numbers" do
      org = create(:organization)
      2.times { create(:organization_discussion_post, organization: org) }
      org.discussion_posts.last.destroy
      assert_equal 1, org.discussion_posts.count
      assert_equal 3, create(:organization_discussion_post, organization: org)[:number]
    end

    test "uses different sequences for different organizations" do
      assert_equal 1, create(:organization_discussion_post,
                             organization: create(:organization))[:number]
      assert_equal 1, create(:organization_discussion_post,
                             organization: create(:organization))[:number]
    end
  end

  context "#async_viewer_can_pin?" do
    test "author can pin" do
      assert @post.async_viewer_can_pin?(@post.user).sync
    end

    test "regular org member cannot pin" do
      org_member = create(:user)
      @post.organization.add_member(org_member)

      refute @post.async_viewer_can_pin?(org_member).sync
    end

    test "org admin can pin" do
      org_admin = create(:user)
      @post.organization.add_admin(org_admin)

      assert @post.async_viewer_can_pin?(org_admin).sync
    end
  end

  context "#async_readable_by?" do
    test "resolves to false if the viewer is nil and post is private" do
      refute @post.async_readable_by?(nil).sync
    end

    test "resolves to false for private post if the viewer is not a member of the org" do
      refute @post.async_readable_by?(create(:user)).sync
    end

    test "resolves to true if the post is public" do
      assert @public_post.async_readable_by?(create(:user)).sync
    end

    test "resolves to true if post is private but the viewer is an org admin" do
      assert @post.async_readable_by?(@org.admin).sync
    end

    test "resolves to true if the post is private but the viewer is an org member" do
      assert @post.async_readable_by?(@org_member).sync
    end
  end

  context "#title_changed?" do
    test "false if UTF-8 title doesn't change" do
      post = create(:organization_discussion_post, organization: @org, title: "caractères spéciaux")
      refute_predicate post, :title_changed?

      post.title = "caractères spéciaux"
      refute_predicate post, :title_changed?
    end

    test "true if UTF-8 title changes" do
      post = create(:organization_discussion_post, organization: @org, title: "caractères spéciaux")
      refute_predicate post, :title_changed?

      post.title = "caractères spéciaux - foo bar"
      assert_predicate post, :title_changed?
    end
  end

  [:title, :body].each do |field|
    test "supports emoji for #{field}" do
      post = create(:organization_discussion_post, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(post, field)
    end
  end
end
