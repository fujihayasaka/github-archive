# typed: true
# frozen_string_literal: true

require "test_helper"

class DraftIssueReferenceFilterTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @repo = create(:public_repository)
    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)

    @private_repo_admin = create(:user)
    @private_repo = create(:private_repository, owner: @private_repo_admin)
    @private_issue = create(:issue, repository: @private_repo, user: @private_repo_admin)
    @private_pull = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @private_repo_admin)
  end

  context "#first_reference" do
    test "identifies a single full URL issue reference" do
      filter = DraftIssueReferenceFilter.new(text: @issue.permalink, viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "identifies a single shortened issue reference" do
      filter = DraftIssueReferenceFilter.new(text: "#{@repo.nwo}##{@issue.number}", viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "identifies a single full URL pull request reference" do
      filter = DraftIssueReferenceFilter.new(text: @pull.permalink, viewer: @user)
      assert_equal @pull, filter.first_reference
    end

    test "identifies a single shortened pull request reference" do
      filter = DraftIssueReferenceFilter.new(text: "#{@repo.nwo}##{@pull.number}", viewer: @user)
      assert_equal @pull, filter.first_reference
    end

    test "recognizes a single reference despite leading and trailing whitespace" do
      filter = DraftIssueReferenceFilter.new(text: "  #{@issue.permalink}\t", viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "recognizes a single reference despite a trailing slash" do
      filter = DraftIssueReferenceFilter.new(text: "#{@issue.permalink}/", viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "recognizes a single refrence despite a trailing pound" do
      filter = DraftIssueReferenceFilter.new(text: "#{@issue.permalink}#", viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "recognizes a single refrence with a hash param" do
      filter = DraftIssueReferenceFilter.new(text: "#{@issue.permalink}#my-placeholder", viewer: @user)
      assert_equal @issue, filter.first_reference
    end

    test "returns nil if there are multiple references in the text" do
      filter = DraftIssueReferenceFilter.new(text: "#{@issue.permalink} and #{@pull.permalink}", viewer: @user)
      assert_nil filter.first_reference
    end

    test "returns nil if there are no references in the text" do
      filter = DraftIssueReferenceFilter.new(text: "#{@repo.nwo} is ##{@issue.number}", viewer: @user)
      assert_nil filter.first_reference
    end

    test "returns nil for a quoted reference" do
      filter = DraftIssueReferenceFilter.new(text: "`#{@repo.nwo}##{@issue.number}`", viewer: @user)
      assert_nil filter.first_reference
    end

    test "returns nil for a keyword-prefixed reference" do
      filter = DraftIssueReferenceFilter.new(text: "Closes #{@repo.nwo}##{@issue.number}", viewer: @user)
      assert_nil filter.first_reference
    end

    test "returns nil for an issue reference the user cannot access" do
      filter = DraftIssueReferenceFilter.new(text: "#{@private_repo.nwo}##{@private_issue.number}", viewer: @user)
      assert_nil filter.first_reference
    end

    test "returns nil for a pull request reference the user cannot access" do
      filter = DraftIssueReferenceFilter.new(text: "#{@private_repo.nwo}##{@private_pull.number}", viewer: @user)
      assert_nil filter.first_reference
    end
  end

  context "#references" do
    test "identifies multiple full URL issue references" do
      filter = DraftIssueReferenceFilter.new(text: "#{@issue.permalink} #{@pull.permalink}", viewer: @user)
      assert_equal [@issue, @pull], filter.references
    end

    test "returns empty array if other text is present and multi_refs flag is set to false" do
      filter = DraftIssueReferenceFilter.new(text: "deploy #{@pull.permalink} to resolve #{@issue.permalink}", viewer: @user)
      assert_empty filter.references
    end

    test "returns multiple references if other text present and multi_refs flag is on" do
      filter = DraftIssueReferenceFilter.new(text: "deploy #{@pull.permalink} to resolve #{@issue.permalink}", viewer: @user, multi_refs: true)
      assert_equal [@pull, @issue], filter.references
    end
  end
end
