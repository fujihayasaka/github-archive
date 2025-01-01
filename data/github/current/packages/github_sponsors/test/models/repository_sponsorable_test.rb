# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySponsorableTest < GitHub::TestCase
  context "validations" do
    test "requires repository" do
      repo_sponsorable = RepositorySponsorable.new
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:repository], "must exist"
    end

    test "requires sponsorable" do
      repo_sponsorable = RepositorySponsorable.new
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:sponsorable], "must exist"
    end

    test "requires sponsorable to have a Sponsors listing" do
      user_wo_listing = create(:user)
      repo_sponsorable = RepositorySponsorable.new(sponsorable: user_wo_listing)
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:sponsorable], "must have a published GitHub Sponsors profile"
    end

    test "does not validate sponsorable has a Sponsors listing when skip_sponsorable_can_be_sponsored_check=true" do
      user_wo_listing = create(:user)
      repo_sponsorable = build(:repository_sponsorable, sponsorable: user_wo_listing)
      repo_sponsorable.skip_sponsorable_can_be_sponsored_check = true
      assert_predicate repo_sponsorable, :valid?
    end

    test "requires sponsorable to have an approved Sponsors listing" do
      user_w_non_approved_listing = create(:user, :verified)
      create(:sponsors_listing, sponsorable: user_w_non_approved_listing)
      repo_sponsorable = RepositorySponsorable.new(sponsorable: user_w_non_approved_listing)
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:sponsorable], "must have a published GitHub Sponsors profile"
    end

    test "does not validate sponsorable has an approved Sponsors listing when skip_sponsorable_can_be_sponsored_check=true" do
      user_w_non_approved_listing = create(:user, :verified)
      create(:sponsors_listing, sponsorable: user_w_non_approved_listing)
      repo_sponsorable = build(:repository_sponsorable, sponsorable: user_w_non_approved_listing)
      repo_sponsorable.skip_sponsorable_can_be_sponsored_check = true
      assert_predicate repo_sponsorable, :valid?
    end

    test "requires unique repository-sponsorable-source combination" do
      repo_sponsorable = create(:repository_sponsorable)
      dupe_repo_sponsorable = RepositorySponsorable.new(repository: repo_sponsorable.repository,
        sponsorable: repo_sponsorable.sponsorable, source: repo_sponsorable.source)
      refute_predicate dupe_repo_sponsorable, :valid?
      assert_includes dupe_repo_sponsorable.errors[:sponsorable_id], "has already been taken"
    end

    test "does not validate repository-sponsorable-source combination is unique when skip_uniqueness_check=true" do
      repo_sponsorable = create(:repository_sponsorable)
      dupe_repo_sponsorable = RepositorySponsorable.new(repository: repo_sponsorable.repository,
        sponsorable: repo_sponsorable.sponsorable, source: repo_sponsorable.source)
      dupe_repo_sponsorable.skip_uniqueness_check = true
      assert_predicate dupe_repo_sponsorable, :valid?
    end

    test "requires source" do
      repo_sponsorable = RepositorySponsorable.new
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:source], "is not included in the list"
    end

    test "requires valid source" do
      error = assert_raises(ArgumentError) do
        RepositorySponsorable.new(source: "invalid")
      end
      assert_equal "'invalid' is not a valid source", error.message
    end

    test "requires repo to be owned by sponsorable when source=owner" do
      rando = create(:user)
      some_repo = create(:repository)
      repo_sponsorable = RepositorySponsorable.new(source: :owner, repository: some_repo, sponsorable: rando)
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:sponsorable], "must be the owner of repository #{some_repo.nwo}"
    end

    test "requires a funding file when source=repo_funding_file" do
      sponsorable = create(:user)
      repo = create(:repository)
      repo_sponsorable = RepositorySponsorable.new(source: :repo_funding_file, repository: repo,
        sponsorable: sponsorable)
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:repository], "must have a funding.yml"
    end

    test "requires a global funding file when source=global_funding_file" do
      sponsorable = create(:user)
      repo = create(:repository)
      repo_sponsorable = RepositorySponsorable.new(source: :global_funding_file, repository: repo,
        sponsorable: sponsorable)
      refute_predicate repo_sponsorable, :valid?
      assert_includes repo_sponsorable.errors[:repository], "must have a global funding.yml"
    end
  end
end
