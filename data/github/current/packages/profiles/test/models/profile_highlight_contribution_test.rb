# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfileHighlightContributionTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @email = create(:user_email, :verified, user: @user)
    @badge = create(:profile_highlight, user: @user)
    @repos = create_list(:repository, 2).each do |repo|
      create(:profile_highlight_contribution, profile_highlight: @badge, repository: repo, contributor_email: @email)
    end
  end

  context "validation" do
    test "highlight + repository + email combo needs to be unique" do
      entry = ProfileHighlightContribution.create(
        repository: @repos[0],
        contributor_email: @email,
        profile_highlight: @badge
      )

      refute entry.valid?
    end
  end

  context "group_by_repository scope" do
    test "returns contributions that have not been ignored" do
      results = @badge.profile_highlight_contributions.group_by_repository

      assert_equal(2, results.length)
      assert_same_elements(@repos.pluck(:id), results.pluck(:repository_id))
    end

    test "returns unique repositories only" do
      another_email = create(:user_email, :verified, user: @user)
      create(:profile_highlight_contribution, profile_highlight: @badge, repository: @repos[0], contributor_email: another_email)

      assert_equal(3, ProfileHighlightContribution.where(contributor_email: [@email.email, another_email.email]).length)

      results = @badge.profile_highlight_contributions.group_by_repository

      assert_equal(2, results.length)
      assert_same_elements(@repos.pluck(:id), results.pluck(:repository_id))
    end
  end

  context "ignore" do
    test "profile highlight contribution eligibility is false when the last contribution is ignored" do
      @badge.profile_highlight_contributions.first.update_attribute(:ignore, true)

      assert @badge.eligible?

      @badge.profile_highlight_contributions.second.update_attribute(:ignore, true)

      refute @badge.eligible?
    end

    test "profile highlight contribution eligibility remains true when at least one contribution is not ignored" do
      assert @badge.eligible?

      @badge.profile_highlight_contributions.first.update_attribute(:ignore, true)

      assert @badge.eligible?
    end

    test "profile highlight contribution eligibility becomes true when one contribution is un-ignored" do
      @badge.profile_highlight_contributions.first.update_attribute(:ignore, true)
      @badge.profile_highlight_contributions.second.update_attribute(:ignore, true)

      refute @badge.eligible?

      @badge.profile_highlight_contributions.second.update_attribute(:ignore, false)

      assert @badge.eligible?
    end
  end
end
