# typed: false
# frozen_string_literal: true

require "test_helper"

class AcvContributorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email = create(:user_email, :verified, user: @user)
    @repos = create_list(:repository, 2).each do |repo|
      create(:acv_contributor,
        repository: repo,
        contributor_email: @email,
      )
    end
  end

  context "validation" do
    test "email + repository combo needs to be unique" do
      entry = AcvContributor.create(
        repository: @repos[0],
        contributor_email: @email
      )
      refute entry.valid?
    end
  end

  context "group_by_repository scope" do
    test "returns acv repository contributions" do
      results = AcvContributor.group_by_repository([@email.email])

      assert_equal(2, results.length)
      assert_same_elements(@repos.pluck(:id), results.pluck(:repository_id))
    end

    test "returns unique repositories only" do
      another_email = create(:user_email, :verified, user: @user)
      create(:acv_contributor,
        repository: @repos[0],
        contributor_email: another_email,
      )

      assert_equal(3, AcvContributor.where(contributor_email: [@email.email, another_email.email]).length)

      results = AcvContributor.group_by_repository([@email.email, another_email.email])

      assert_equal(2, results.length)
      assert_same_elements(@repos.pluck(:id), results.pluck(:repository_id))
    end

    test "excludes the entries with the ignore flag" do
      ignored = AcvContributor.find_by(contributor_email: @email.email)
      ignored.ignore = true
      ignored.save!
      results = AcvContributor.group_by_repository(@email.email)

      assert_equal(1, results.length)
      refute_includes(results, ignored)
    end
  end

  context "includes_ignored scope" do
    test "returns all acv repository contribution by supplied emails" do
      another_email = create(:user_email, :verified, user: @user)
      create(:acv_contributor,
        repository: @repos[0],
        contributor_email: another_email,
      )
      ignored = AcvContributor.first
      ignored.ignore = true
      ignored.save!

      results = AcvContributor.includes_ignored([@email.email, another_email.email])

      assert_equal(3, results.length)
    end
  end
end
