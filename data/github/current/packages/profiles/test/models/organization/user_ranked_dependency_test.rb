# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserRankedDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "returns nothing if there are no verified company organizations" do
    assert_empty Organization.compute_ranked_ids(user: @user)
  end

  test "returns verified company organizations if present" do
    org = create(:organization)

    org.add_member(@user)
    org.publicize_member(@user)

    @user.profile_company = "works at @#{org}"
    @user.save!

    assert_equal [org.id], Organization.compute_ranked_ids(user: @user)
  end

  test "returns orgs in the order of most to least committed, excluding those with no contributions" do
    org_a,  org_b,  org_c  = create_list(:organization, 3)
    repo_a, repo_b, repo_c = [org_a, org_b].map { |o| create(:repository, owner: o) }

    create(:commit_contribution, :with_summaries, repository: repo_b, user: @user, commit_count: 2, committed_date: Date.today)
    create(:commit_contribution, :with_summaries, repository: repo_a, user: @user, commit_count: 1, committed_date: Date.today)

    assert_equal [org_b.id, org_a.id], Organization.compute_ranked_ids(user: @user)
  end

  test "does not return nil for non-org repository contributions" do
    repo = create(:repository)

    CommitContribution.create!(repository: repo, user: @user, commit_count: 1, committed_date: Date.current)

    assert_empty Organization.compute_ranked_ids(user: @user)
  end

  test "includes verified company organizations at the lead of the list if present (with no duplication)" do
    org_a,  org_b,  org_c  = create_list(:organization, 3)
    repo_a, repo_b, repo_c = [org_a, org_b].map { |o| create(:repository, owner: o) }

    org_a.add_member(@user)
    org_a.publicize_member(@user)
    @user.profile_company = "works at @#{org_a}"
    @user.save!

    create(:commit_contribution, :with_summaries, repository: repo_b, user: @user, commit_count: 2, committed_date: Date.today)
    create(:commit_contribution, :with_summaries, repository: repo_a, user: @user, commit_count: 1, committed_date: Date.today)

    assert_equal [org_a.id, org_b.id], Organization.compute_ranked_ids(user: @user)
  end

  test "returns no orgs for a large scale contributor with no verified profile orgs" do
    org = create(:organization)
    repo = create(:repository, owner: org)

    create(:commit_contribution, :with_summaries, repository: repo, user: @user, commit_count: 2, committed_date: Date.today)

    assert_equal [org.id], Organization.compute_ranked_ids(user: @user)

    @user.flag_as_large_scale_contributor!

    assert_empty Organization.compute_ranked_ids(user: @user)
  end
end
