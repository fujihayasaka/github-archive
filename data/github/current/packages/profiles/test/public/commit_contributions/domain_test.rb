# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionsDomainTest < GitHub::TestCase

  fixtures do
    @user_with_summaries_and_contributions = create(:user)
    @user_with_only_summaries = create(:user)
    @user_with_only_contributions = create(:user)

    @repo_with_summaries_and_contributions = create(:repository)
    @repo_with_only_summaries = create(:repository)
    @repo_with_only_contributions = create(:repository)

    @contribution_date = Date.today.freeze
    @date_range = Range.new(1.week.ago.to_date, Date.today).freeze
    counts = Array.new(365, 0).fill(1, @contribution_date.yday - 1, 1)
    create(:commit_contribution_summary, user: @user_with_only_summaries, repository: @repo_with_only_summaries, year: @contribution_date.year, counts: counts)
    create(:commit_contribution, :with_summaries, user: @user_with_summaries_and_contributions, repository: @repo_with_summaries_and_contributions, commit_count: 1, committed_date: @contribution_date)
    create(:commit_contribution, user: @user_with_only_contributions, repository: @repo_with_only_contributions, commit_count: 1, committed_date: @contribution_date)
  end

  setup do
    @domain = CommitContributions.domain
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(CommitContributions::Domain) }
  def domain
    T.must(@domain)
  end

  context "is_contributor?" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_equal false, domain.is_contributor?(user: @user_with_only_summaries)
        assert_equal true, domain.is_contributor?(user: @user_with_summaries_and_contributions)
        assert_equal true, domain.is_contributor?(user: @user_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        assert_equal true, domain.is_contributor?(user: @user_with_only_summaries)
        assert_equal true, domain.is_contributor?(user: @user_with_summaries_and_contributions)
        assert_equal false, domain.is_contributor?(user: @user_with_only_contributions)
      end
    end
  end

  context "contributed_repo_ids" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.contributed_repo_ids(user: @user_with_only_summaries)
        refute_empty domain.contributed_repo_ids(user: @user_with_summaries_and_contributions)
        refute_empty domain.contributed_repo_ids(user: @user_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.contributed_repo_ids(user: @user_with_only_summaries)
        refute_empty domain.contributed_repo_ids(user: @user_with_summaries_and_contributions)
        assert_empty domain.contributed_repo_ids(user: @user_with_only_contributions)
      end
    end
  end

  context "contributed_user_ids" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.contributed_user_ids(repository: @repo_with_only_summaries)
        refute_empty domain.contributed_user_ids(repository: @repo_with_summaries_and_contributions)
        refute_empty domain.contributed_user_ids(repository: @repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.contributed_user_ids(repository: @repo_with_only_summaries)
        refute_empty domain.contributed_user_ids(repository: @repo_with_summaries_and_contributions)
        assert_empty domain.contributed_user_ids(repository: @repo_with_only_contributions)
      end
    end
  end

  context "contributed_user_ids_by_recency" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_summaries, limit: 10)
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_summaries_and_contributions, limit: 10)
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_contributions, limit: 10)

        assert_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_summaries, limit: 10)
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_summaries_and_contributions, limit: 10)
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_contributions, limit: 10)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_summaries, limit: 10)
        refute_empty domain.contributed_user_ids_by_recency(repository: @repo_with_summaries_and_contributions, limit: 10)
        assert_empty domain.contributed_user_ids_by_recency(repository: @repo_with_only_contributions, limit: 10)
      end
    end
  end

  context "has_recent_contributions?" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_equal false, domain.has_recent_contributions?(repository_ids: [@repo_with_only_summaries], since: @date_range.begin)
        assert_equal true, domain.has_recent_contributions?(repository_ids: [@repo_with_summaries_and_contributions], since: @date_range.begin)
        assert_equal true, domain.has_recent_contributions?(repository_ids: [@repo_with_only_contributions], since: @date_range.begin)
      end
    else
      test "uses commit_contribution_summaries" do
        assert_equal true, domain.has_recent_contributions?(repository_ids: [@repo_with_only_summaries], since: @date_range.begin)
        assert_equal true, domain.has_recent_contributions?(repository_ids: [@repo_with_summaries_and_contributions], since: @date_range.begin)
        assert_equal false, domain.has_recent_contributions?(repository_ids: [@repo_with_only_contributions], since: @date_range.begin)
      end
    end
  end

  context "commit_count_for_repository" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_equal 0, domain.commit_count_for_repository(@repo_with_only_summaries)
        assert_equal 1, domain.commit_count_for_repository(@repo_with_summaries_and_contributions)
        assert_equal 1, domain.commit_count_for_repository(@repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        assert_equal 1, domain.commit_count_for_repository(@repo_with_only_summaries)
        assert_equal 1, domain.commit_count_for_repository(@repo_with_summaries_and_contributions)
        assert_equal 0, domain.commit_count_for_repository(@repo_with_only_contributions)
      end
    end
  end

  context "commit_contributions_for" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_only_summaries)
        refute_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_summaries_and_contributions)
        refute_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_only_summaries)
        refute_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_summaries_and_contributions)
        assert_empty domain.commit_contributions_for(date_range: @date_range, user: @user_with_only_contributions)
      end
    end
  end

  context "repository_contribution_history" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_only_summaries, users: [@user_with_only_summaries]))[:commits])[@user_with_only_summaries.git_author_email]
        refute_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_summaries_and_contributions, users: [@user_with_summaries_and_contributions]))[:commits])[@user_with_summaries_and_contributions.git_author_email]
        refute_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_only_contributions, users: [@user_with_only_contributions]))[:commits])[@user_with_only_contributions.git_author_email]
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_only_summaries, users: [@user_with_only_summaries]))[:commits])[@user_with_only_summaries.git_author_email]
        refute_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_summaries_and_contributions, users: [@user_with_summaries_and_contributions]))[:commits])[@user_with_summaries_and_contributions.git_author_email]
        assert_empty T.must(T.must(domain.repository_contribution_history(repository: @repo_with_only_contributions, users: [@user_with_only_contributions]))[:commits])[@user_with_only_contributions.git_author_email]
      end
    end
  end

  context "repository_commit_activity" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.repository_commit_activity(repository: @repo_with_only_summaries)
        refute_empty domain.repository_commit_activity(repository: @repo_with_summaries_and_contributions)
        refute_empty domain.repository_commit_activity(repository: @repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.repository_commit_activity(repository: @repo_with_only_summaries)
        refute_empty domain.repository_commit_activity(repository: @repo_with_summaries_and_contributions)
        assert_empty domain.repository_commit_activity(repository: @repo_with_only_contributions)
      end
    end
  end

  context "top_repository_contributors" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.top_repository_contributors(repository: @repo_with_only_summaries, limit: 1, viewer: nil)
        refute_empty domain.top_repository_contributors(repository: @repo_with_summaries_and_contributions, limit: 1, viewer: nil)
        refute_empty domain.top_repository_contributors(repository: @repo_with_only_contributions, limit: 1, viewer: nil)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.top_repository_contributors(repository: @repo_with_only_summaries, limit: 1, viewer: nil)
        refute_empty domain.top_repository_contributors(repository: @repo_with_summaries_and_contributions, limit: 1, viewer: nil)
        assert_empty domain.top_repository_contributors(repository: @repo_with_only_contributions, limit: 1, viewer: nil)
      end
    end
  end

  context "top_repository_contributor_ids" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.top_repository_contributor_ids(repository: @repo_with_only_summaries, limit: 1)
        refute_empty domain.top_repository_contributor_ids(repository: @repo_with_summaries_and_contributions, limit: 1)
        refute_empty domain.top_repository_contributor_ids(repository: @repo_with_only_contributions, limit: 1)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.top_repository_contributor_ids(repository: @repo_with_only_summaries, limit: 1)
        refute_empty domain.top_repository_contributor_ids(repository: @repo_with_summaries_and_contributions, limit: 1)
        assert_empty domain.top_repository_contributor_ids(repository: @repo_with_only_contributions, limit: 1)
      end
    end
  end

  context "top_contributed_repository_ids" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.top_contributed_repository_ids(user: @user_with_only_summaries, limit: 1)
        refute_empty domain.top_contributed_repository_ids(user: @user_with_summaries_and_contributions, limit: 1)
        refute_empty domain.top_contributed_repository_ids(user: @user_with_only_contributions, limit: 1)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.top_contributed_repository_ids(user: @user_with_only_summaries, limit: 1)
        refute_empty domain.top_contributed_repository_ids(user: @user_with_summaries_and_contributions, limit: 1)
        assert_empty domain.top_contributed_repository_ids(user: @user_with_only_contributions, limit: 1)
      end
    end
  end

  context "first_repository_contribution_date" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_nil domain.first_repository_contribution_date(repository: @repo_with_only_summaries)
        refute_nil domain.first_repository_contribution_date(repository: @repo_with_summaries_and_contributions)
        refute_nil domain.first_repository_contribution_date(repository: @repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_nil domain.first_repository_contribution_date(repository: @repo_with_only_summaries)
        refute_nil domain.first_repository_contribution_date(repository: @repo_with_summaries_and_contributions)
        assert_nil domain.first_repository_contribution_date(repository: @repo_with_only_contributions)
      end
    end
  end

  context "days_with_commits_count_by_repo" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_empty domain.days_with_commits_count_by_repo(user: @user_with_only_summaries, since: @date_range.begin)
        refute_empty domain.days_with_commits_count_by_repo(user: @user_with_summaries_and_contributions, since: @date_range.begin)
        refute_empty domain.days_with_commits_count_by_repo(user: @user_with_only_contributions, since: @date_range.begin)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_empty domain.days_with_commits_count_by_repo(user: @user_with_only_summaries, since: @date_range.begin)
        refute_empty domain.days_with_commits_count_by_repo(user: @user_with_summaries_and_contributions, since: @date_range.begin)
        assert_empty domain.days_with_commits_count_by_repo(user: @user_with_only_contributions, since: @date_range.begin)
      end
    end
  end

  context "contributors_count_for_repository" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_equal 0, domain.contributors_count_for_repository(@repo_with_only_summaries)
        assert_equal 1, domain.contributors_count_for_repository(@repo_with_summaries_and_contributions)
        assert_equal 1, domain.contributors_count_for_repository(@repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        assert_equal 1, domain.contributors_count_for_repository(@repo_with_only_summaries)
        assert_equal 1, domain.contributors_count_for_repository(@repo_with_summaries_and_contributions)
        assert_equal 0, domain.contributors_count_for_repository(@repo_with_only_contributions)
      end
    end
  end

  context "last_contribution_date" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_nil domain.last_contribution_date(user: @user_with_only_summaries, repository: @repo_with_only_summaries)
        refute_nil domain.last_contribution_date(user: @user_with_summaries_and_contributions, repository: @repo_with_summaries_and_contributions)
        refute_nil domain.last_contribution_date(user: @user_with_only_contributions, repository: @repo_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_nil domain.last_contribution_date(user: @user_with_only_summaries, repository: @repo_with_only_summaries)
        refute_nil domain.last_contribution_date(user: @user_with_summaries_and_contributions, repository: @repo_with_summaries_and_contributions)
        assert_nil domain.last_contribution_date(user: @user_with_only_contributions, repository: @repo_with_only_contributions)
      end
    end
  end

  context "first_contribution_date" do
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "does not use commit_contribution_summaries" do
        assert_nil domain.first_contribution_date(user: @user_with_only_summaries)
        refute_nil domain.first_contribution_date(user: @user_with_summaries_and_contributions)
        refute_nil domain.first_contribution_date(user: @user_with_only_contributions)
      end
    else
      test "uses commit_contribution_summaries" do
        refute_nil domain.first_contribution_date(user: @user_with_only_summaries)
        refute_nil domain.first_contribution_date(user: @user_with_summaries_and_contributions)
        assert_nil domain.first_contribution_date(user: @user_with_only_contributions)
      end
    end
  end
end
