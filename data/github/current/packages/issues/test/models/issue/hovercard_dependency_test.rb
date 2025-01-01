# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueHovercardDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @anon = create(:user)

    @org = create(:organization, admin: @user)
    @private_repo = create(:private_repository, owner: @org)

    @first_ever_issue = create(:issue, user: @user)

    @issue = create(:issue, repository: @private_repo, user: @user)
  end

  context "user_hovercard_parent" do
    test "returns the containing repository" do
      assert_equal @private_repo, @issue.user_hovercard_parent
    end
  end

  context "creator context" do
    context "when the organization has less than REPO_LIMIT_FOR_ORG_HOVERCARD" do
      test "returns status if this is the first user issue in the org" do
        context = @issue.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

        assert_equal "Opened this issue (their first in @#{@org})", context.message

        # viewer that can't read the repo cannot see this status
        assert_nil @issue.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)
        assert_nil @issue.user_hovercard_context_for(@user, viewer: nil, limit: :creator)
      end
    end

    context "when the organization is greater than REPO_LIMIT_FOR_ORG_HOVERCARD" do
      test "returns status if this is the first user issue in this repo" do
        Issue::HovercardDependency.stub_const(:REPO_LIMIT_FOR_ORG_HOVERCARD, 1) do
          second_repo = create(:private_repository, owner: @org)
          context = @issue.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

          assert_equal "Opened this issue (their first in #{@private_repo.nwo})", context.message

          assert_nil @issue.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)
          assert_nil @issue.user_hovercard_context_for(@user, viewer: nil, limit: :creator)
        end
      end

      test "returns status if the creator has created other issues in this repo & org" do
        Issue::HovercardDependency.stub_const(:REPO_LIMIT_FOR_ORG_HOVERCARD, 1) do
          second_issue_in_repo = create(:issue, repository: @private_repo, user: @user)

          context = second_issue_in_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

          assert_equal "Opened this issue", context.message
        end
      end
    end

    test "returns status if this is the first issue the user ever created" do
      context = @first_ever_issue.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this issue (their first ever)", context.message
    end

    test "returns status if this is the first user issue in this repo, but not the first in the org" do
      other_repo = create(:private_repository, owner: @org)
      first_issue_in_other_org_repo = create(:issue, repository: other_repo, user: @user)

      context = first_issue_in_other_org_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this issue (their first in #{other_repo.nwo})", context.message
    end

    test "returns status if the creator has created other issues in this repo & org" do
      second_issue_in_repo = create(:issue, repository: @private_repo, user: @user)

      context = second_issue_in_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this issue", context.message
    end

    test "returns status if this is the first user issue in a non-org repo" do
      # ensure it does not get confused with contributions to other non-org repos
      other_user_repo = create(:repository, owner: @user)
      create(:issue, repository: other_user_repo, user: @user)

      # create first contribution in another repo
      user_repo = create(:repository, owner: @user)
      first_issue = create(:issue, repository: user_repo, user: @user)

      context = first_issue.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this issue (their first in #{user_repo.nwo})", context.message
    end

    test "returns nil if the repository is private and viewer is not a member that can view the issue" do
      context = @issue.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)

      assert_nil context
    end

    test "returns nil if the user has no relation to the issue" do
      context = @issue.user_hovercard_context_for(@anon, viewer: @user, limit: :creator)

      assert_nil context
    end
  end
end
