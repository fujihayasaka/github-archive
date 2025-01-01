# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BackfillCommitContributionSummariesJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    date = Date.new(2024, 1, 7)
    create(:commit_contribution, user: @user, repository: @repo, committed_date: date, commit_count: 42)
  end

  test "records commit contribution summaries for a repository" do
    disable_feature_flag(:skip_commit_contributions, @repo)
    assert_changes -> { CommitContributionSummary.where(repository: @repo).count }, from: 0, to: 1 do
      BackfillCommitContributionSummariesJob.perform_now(@repo.id)
    end

    assert summary = CommitContributionSummary.where(repository: @repo).first!
    assert_equal 2024, summary.year
    assert_equal Array.new(366, 0).fill(42, 6, 1), summary.counts
  end

  test "backfills for a specific user" do
    disable_feature_flag(:skip_commit_contributions, @repo)
    other_user = create(:user)
    @repo.add_member(other_user)
    create(:commit_contribution, user: other_user, repository: @repo, committed_date: Date.new(2024, 1, 7), commit_count: 42)

    assert_changes -> { CommitContributionSummary.where(repository: @repo).count }, from: 0, to: 1 do
      BackfillCommitContributionSummariesJob.perform_now(@repo.id, user_id: @user.id)
    end

    assert_empty CommitContributionSummary.where(repository: @repo, user: other_user)
    assert summary = CommitContributionSummary.where(repository: @repo, user: @user).first!
    assert_equal 2024, summary.year
    assert_equal Array.new(366, 0).fill(42, 6, 1), summary.counts
  end

  test "backfills from git data when not using commit_contributions", skip_enterprise: true do
    enable_feature_flag(:skip_commit_contributions, @repo)
    example_repo :defunkt_facebox, @repo

    other_user = create(:user, email: "chris@ozmm.org")
    @repo.add_member(other_user)

    create(:commit_contribution, user: other_user, repository: @repo, committed_date: Date.new(2024, 1, 7), commit_count: 42)

    refute_empty CommitContribution.all
    assert_empty CommitContributionSummary.for_repository(@repo).for_user(@user)
    assert_empty CommitContributionSummary.for_repository(@repo).for_user(other_user)

    assert_changes -> { CommitContributionSummary.where(repository: @repo).count }, from: 0, to: 1 do
      BackfillCommitContributionSummariesJob.perform_now(@repo.id)
    end

    assert_empty CommitContribution.all
    assert_empty CommitContributionSummary.for_repository(@repo).for_user(@user)
    refute_empty CommitContributionSummary.for_repository(@repo).for_user(other_user)
  end

  test "does nothing when a nonexistent user is given" do
    @user.destroy

    CommitContributionSummary.expects(:backfill_repository).never
    BackfillCommitContributionSummariesJob.perform_now(@repo.id, user_id: @user.id)
  end

  test "does nothing when a nonexistent repository is given" do
    @repo.destroy

    CommitContributionSummary.expects(:backfill_repository).never
    BackfillCommitContributionSummariesJob.perform_now(@repo.id)
  end

  test "records commit contribution summaries for a repository in multi-tenant enterprise" do
    on_multi_tenant_enterprise do
      emu = create(:emu)
      org = create(:organization, :enterprise_managed_organization, business: emu.enterprise_managed_business, admin: emu)
      repo = create(:repository, owner: org)

      date = Date.new(2024, 1, 7)
      create(:commit_contribution, user: emu, repository: repo, committed_date: date, commit_count: 42)

      assert_changes -> { CommitContributionSummary.where(repository: repo).count }, from: 0, to: 1 do
        BackfillCommitContributionSummariesJob.perform_now(repo.id)
      end

      summary = CommitContributionSummary.where(repository: repo).first!
      assert_equal 2024, summary.year
      assert_equal Array.new(366, 0).fill(42, 6, 1), summary.counts
    end
  end
end
