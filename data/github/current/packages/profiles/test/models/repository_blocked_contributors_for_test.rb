# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBlockedContributorsForTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @contributor = create(:user, login: "spammy", plan: "medium")
    @blocker = create(:user, login: "safia", plan: "medium")
    create(:commit_contribution, :with_summaries, repository: @repo, user: @contributor)
  end

  test "returns a list of blocked contributors" do
    assert @repo.contributor?(@contributor)

    only = [AddToSearchIndexJob, CheckForSpamJob, IgnoreUserJob, UserContributionsBackfillJob]
    perform_enqueued_jobs(only: only) { @blocker.block(@contributor) }
    assert @contributor.blocked_by?(@blocker)

    assert_includes @repo.blocked_contributors_for(@blocker), @contributor
  end

  test "returns empty list if user hasn't blocked anyone" do
    assert_empty @blocker.ignored
    assert_empty @repo.blocked_contributors_for(@blocker)
  end

  test "returns empty list if user hasn't blocked any contributors to the repo" do
    rando = create(:user, login: "rando")
    refute @repo.contributor?(rando)

    only = [AddToSearchIndexJob, CheckForSpamJob, IgnoreUserJob, UserContributionsBackfillJob]
    perform_enqueued_jobs(only: only) { @blocker.block(rando) }
    assert rando.blocked_by?(@blocker)

    assert_empty @repo.blocked_contributors_for(@blocker)
  end
end
