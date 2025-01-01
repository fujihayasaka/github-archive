# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuePinnedIssuesDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @collaborator = create(:user)
    @repo.add_member(@collaborator)

    @issue1 = create(:issue, repository: @repo, user: @user)
    @issue2 = create(:issue, repository: @repo, user: @user)
    @issue3 = create(:issue, repository: @repo, user: @user)
  end

  context "#reorder_pinned_issues" do
    test "prioritize 3 issues updates all the sorts correctly up" do
      @issue3.pin(actor: @user)
      @issue2.pin(actor: @user)
      @issue1.pin(actor: @user)

      assert_equal [@issue3, @issue2, @issue1], @repo.pinned_issues.map(&:issue)

      @repo.reorder_pinned_issues([@issue2.id, @issue3.id, @issue1.id])
      @repo.reload

      assert_equal [@issue2, @issue3, @issue1], @repo.pinned_issues.map(&:issue)
    end

    test "prioritize 3 issues updates all the sorts correctly up by 1" do
      @issue3.pin(actor: @user)
      @issue2.pin(actor: @user)
      @issue1.pin(actor: @user)

      assert_equal [@issue3, @issue2, @issue1], @repo.pinned_issues.map(&:issue)

      @repo.reorder_pinned_issues([@issue3.id, @issue1.id, @issue2.id])
      @repo.reload

      assert_equal [@issue3, @issue1, @issue2], @repo.pinned_issues.map(&:issue)
    end

    test "prioritize 3 issues updates all the sorts correctly down" do
      @issue1.pin(actor: @user)
      @issue2.pin(actor: @user)
      @issue3.pin(actor: @user)

      assert_equal [@issue1, @issue2, @issue3], @repo.pinned_issues.map(&:issue)

      @repo.reorder_pinned_issues([@issue1.id, @issue3.id, @issue2.id])
      @repo.reload

      assert_equal [@issue1, @issue3, @issue2], @repo.pinned_issues.map(&:issue)
    end

    test "prioritize 3 issues updates all the sorts correctly down 2" do
      @issue1.pin(actor: @user)
      @issue2.pin(actor: @user)
      @issue3.pin(actor: @user)

      assert_equal [@issue1, @issue2, @issue3], @repo.pinned_issues.map(&:issue)

      @repo.reorder_pinned_issues([@issue2.id, @issue3.id, @issue1.id])
      @repo.reload

      assert_equal [@issue2, @issue3, @issue1], @repo.pinned_issues.map(&:issue)
    end

    test "prioritize 2 issues updates all the sorts correctly" do
      @issue2.pin(actor: @user)
      @issue1.pin(actor: @user)

      assert_equal [@issue2, @issue1], @repo.pinned_issues.map(&:issue)

      @repo.reorder_pinned_issues([@issue1.id, @issue2.id])
      @repo.reload

      assert_equal [@issue1, @issue2], @repo.pinned_issues.map(&:issue)
    end

    test "pinning a issue adds the issue to the bottom of the list" do
      @issue1.pin(actor: @user)
      @issue2.pin(actor: @user)

      assert_equal [@issue1, @issue2], @repo.pinned_issues.map(&:issue)

      @issue3.pin(actor: @user)
      @repo.reload

      assert_equal [@issue1, @issue2, @issue3], @repo.pinned_issues.map(&:issue)
    end
  end
end
