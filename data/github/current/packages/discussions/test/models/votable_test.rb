# typed: true
# frozen_string_literal: true

require "test_helper"

class VotableTest < GitHub::TestCase
  include DiscussionsTestHelper

  fixtures do
    create_discussions_authz_fixtures

    @discussion = create(:discussion, repository: @repo)
    @comment = create(:discussion_comment, discussion: @discussion, repository: @repo)

    @private_discussion = create(:discussion, repository: @private_repo)
    @private_comment = create(:discussion_comment, discussion: @private_discussion, repository: @private_repo)

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_comment = create(:discussion_comment, discussion: @org_discussion, repository: @org_repo)

    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_private_comment = create(:discussion_comment, discussion: @org_private_discussion,
      repository: @org_private_repo)

    @org_without_default_permission_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_private_repo,
    )
    @org_without_default_permission_repo_comment = create(:discussion_comment,
      discussion: @org_without_default_permission_repo_discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_comment = create(:discussion_comment,
      discussion: @org_without_default_permission_private_repo_discussion,
      repository: @org_without_default_permission_private_repo,
    )

    @business_internal_discussion = create(:discussion, repository: @business_internal_repo)
    @business_internal_comment = create(:discussion_comment, discussion: @business_internal_discussion,
      repository: @business_internal_repo)
  end

  setup do
    @discussion_matrix = AccessMatrix.new(self)
    @discussion_matrix.setup_subjects(
      repo: @discussion,
      private_repo: @private_discussion,
      org_repo: @org_discussion,
      org_private_repo: @org_private_discussion,
      org_without_default_permission_repo: @org_without_default_permission_repo_discussion,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_discussion,
      business_internal_repo: @business_internal_discussion,
    )

    @comment_matrix = AccessMatrix.new(self)
    @comment_matrix.setup_subjects(
      repo: @comment,
      private_repo: @private_comment,
      org_repo: @org_comment,
      org_private_repo: @org_private_comment,
      org_without_default_permission_repo: @org_without_default_permission_repo_comment,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_comment,
      business_internal_repo: @business_internal_comment,
    )
  end

  context "#total_upvotes" do
    test "returns upvotes for a discussion" do
      create_list(:discussion_vote, 2, upvote: true, discussion: @discussion)

      CalculateDiscussionTotalVotesJob.perform_now(@discussion.id)

      assert_equal 3, @discussion.reload.total_upvotes
    end
  end

  context "#async_vote_for and #async_has_upvoted?" do
    test "when a user has not upvoted on a discussion" do
      assert_nil @discussion.async_vote_for(@owner).sync
      refute @discussion.async_has_upvoted?(@owner).sync
    end

    test "when a user has not upvoted on a discussion comment" do
      assert_nil @comment.async_vote_for(@owner).sync
      refute @comment.async_has_upvoted?(@owner).sync
    end

    test "when a user has upvoted on a discussion" do
      vote = create(:discussion_vote, discussion: @discussion, user: @owner, upvote: true)

      assert_equal vote, @discussion.async_vote_for(@owner).sync
      assert @discussion.async_has_upvoted?(@owner).sync
    end

    test "when a user has upvoted on a discussion comment" do
      vote = create(:discussion_comment_vote, comment: @comment, user: @owner, upvote: true)

      assert_equal vote, @comment.async_vote_for(@owner).sync
      assert @comment.async_has_upvoted?(@owner).sync
    end
  end

  context "#async_upvotable_by? for discussion" do
    test "requires read+ for users" do
      @discussion_matrix.user_scenarios(
        :async_upvotable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when user is spammy" do
      assert_block = lambda do |discussion, user|
        user.update!(spammy: true)

        assert discussion.async_upvotable_by?(user).sync
      end

      refute_block = lambda do |discussion, user|
        user.update!(spammy: true)

        refute discussion.async_upvotable_by?(user).sync
      end

      @discussion_matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end if GitHub.spamminess_check_enabled?

    test "false when user is suspended" do
      assert_block = lambda do |discussion, user|
        user.suspend("Because I felt like it")

        assert discussion.async_upvotable_by?(user).sync
      end

      refute_block = lambda do |discussion, user|
        user.suspend("Because I felt like it")

        refute discussion.async_upvotable_by?(user).sync
      end

      @discussion_matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when user is unverified" do
      refute @discussion.async_upvotable_by?(@unverified).sync
    end if GitHub.email_verification_enabled?

    test "false when user is blocked by author" do
      @discussion.user.block(@rando)

      refute @discussion.async_upvotable_by?(@rando).sync
    end

    test "false when interaction limits are enabled on the repo" do
      User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))

      @discussion_matrix.user_scenarios(
        :async_upvotable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true even when user has already voted the same way" do
      vote = create(:discussion_vote, discussion: @discussion, user: @owner)

      assert @discussion.async_upvotable_by?(@owner).sync

      vote.update!(upvote: true)

      assert @discussion.async_upvotable_by?(@owner).sync
    end
  end

  context "#async_upvotable_by? for discussion comment" do
    test "requires read+ for users" do
      @comment_matrix.user_scenarios(
        :async_upvotable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when user is spammy" do
      assert_block = lambda do |comment, user|
        user.mark_as_spammy

        assert comment.async_upvotable_by?(user).sync
      end

      refute_block = lambda do |comment, user|
        user.mark_as_spammy

        refute comment.async_upvotable_by?(user).sync
      end

      @comment_matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end if GitHub.spamminess_check_enabled?

    test "false when user is suspended" do
      assert_block = lambda do |comment, user|
        user.suspend("Because I felt like it")

        assert comment.async_upvotable_by?(user).sync
      end

      refute_block = lambda do |comment, user|
        user.suspend("Because I felt like it")

        refute comment.async_upvotable_by?(user).sync
      end

      @comment_matrix.user_scenarios_custom(
        assert_block: assert_block,
        refute_block: refute_block,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when user is unverified" do
      refute @comment.async_upvotable_by?(@unverified).sync
    end if GitHub.email_verification_enabled?

    test "false when user is blocked by comment author" do
      @comment.user.block(@rando)

      refute @comment.async_upvotable_by?(@rando).sync
    end

    test "false when user is blocked by discussion author" do
      @discussion.user.block(@rando)

      refute @comment.async_upvotable_by?(@rando).sync
    end

    test "false when interaction limits are enabled on the repo" do
      User::InteractionAbility.stubs(:async_interaction_allowed?).returns(Promise.resolve(false))

      @comment_matrix.user_scenarios(
        :async_upvotable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true even if the user has already voted the same way" do
      vote = create(:discussion_comment_vote, comment: @comment, user: @owner)

      assert @comment.async_upvotable_by?(@owner).sync

      vote.update!(upvote: true)

      assert @comment.async_upvotable_by?(@owner).sync
    end
  end
end
