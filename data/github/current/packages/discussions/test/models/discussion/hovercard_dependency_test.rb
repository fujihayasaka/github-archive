# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionHovercardDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @anon = create(:user)

    @org = create(:organization, admin: @user)
    @private_repo = create(:private_repository, owner: @org, has_discussions: true)

    @first_ever_discussion = create(:discussion, user: @user)

    @discussion = create(:discussion, repository: @private_repo, user: @user)
  end

  context "user_hovercard_parent" do
    test "returns the containing repository" do
      assert_equal @private_repo, @discussion.user_hovercard_parent
    end
  end

  context "creator context" do
    test "returns status if this is the first discussion in the org authored by the user" do
      context = @discussion.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Started this discussion (their first in @#{@org})", context.message

      # viewer that can't read the repo cannot see this status
      assert_nil @discussion.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)
      assert_nil @discussion.user_hovercard_context_for(@user, viewer: nil, limit: :creator)
    end

    test "returns status if this is the first discussion the user ever created" do
      context = @first_ever_discussion.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Started this discussion (their first ever)", context.message
    end

    test "returns status if this is the first user discussion in this repo, but not the first in the org" do
      other_repo = create(:private_repository, owner: @org, has_discussions: true)
      first_discussion_in_other_org_repo = create(:discussion, repository: other_repo, user: @user)

      context = first_discussion_in_other_org_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Started this discussion (their first in #{other_repo.nwo})", context.message
    end

    test "returns status if the creator has created other issues in this repo & org" do
      second_discussion_in_repo = create(:discussion, repository: @private_repo, user: @user)

      context = second_discussion_in_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Started this discussion", context.message
    end

    test "returns status if this is the first user discussion in a non-org repo" do
      # ensure it does not get confused with contributions to other non-org repos
      other_user_repo = create(:repository, owner: @user, has_discussions: true)
      create(:discussion, repository: other_user_repo, user: @user)

      # create first contribution in another repo
      user_repo = create(:repository, owner: @user, has_discussions: true)
      first_discussion = create(:discussion, repository: user_repo, user: @user)

      context = first_discussion.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Started this discussion (their first in #{user_repo.nwo})", context.message
    end

    test "returns nil if the repository is private and viewer is not a member that can view the discussion" do
      context = @discussion.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)

      assert_nil context
    end

    test "returns nil if the user has no relation to the discussion" do
      context = @discussion.user_hovercard_context_for(@anon, viewer: @user, limit: :creator)

      assert_nil context
    end
  end
end
