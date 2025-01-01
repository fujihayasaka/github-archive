# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfileHighlightTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email = create(:user_email, :verified, user: @user)
    @badge = create(:profile_highlight, user: @user)
    @repos = create_list(:repository, 5).each_with_index do |repo, index|
      repo.stargazer_count = (index + 1) * 10
      repo.save!
    end

    @repos.map do |repo|
      create(:profile_highlight_contribution, profile_highlight: @badge, repository: repo, contributor_email: @email)
    end
  end

  context "validation" do
    test "name + user combo needs to be unique" do
      entry = ProfileHighlight.create(
        user: @user,
        highlight_type: 0
      )

      refute entry.valid?
    end
  end

  context "#contribution_count" do
    test "returns number of filtered repositories the user contributed to" do
      assert_equal 5, @badge.contribution_count
    end
  end

  context "#top_repositories" do
    test "returns a limited list of filtered repositories the user contributed to, sorted by star count" do
      sorted_repos = @badge.top_repositories(limit: 5)

      assert_equal(5, sorted_repos.length)
      assert_equal(@repos.reverse, sorted_repos)
    end

    test "returns empty array if user is not a contributor" do
      another_user = create(:user)
      badge = create(:profile_highlight, user: another_user)

      assert_equal([], badge.top_repositories)
    end
  end
end
