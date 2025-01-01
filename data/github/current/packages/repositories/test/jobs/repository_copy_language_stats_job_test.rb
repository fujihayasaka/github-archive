# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryCopyLanguageStatsJobTest < GitHub::TestCase
  include JobTestHelper
  fixtures do
    @grit = create(:repository, from_example: :mojombo_grit)
  end

  test "should return nil if no repo" do
    repo = create(:repository)
    repo.remove(repo.owner)
    repo.purge(synchronous: true)

    assert_nil RepositoryCopyLanguageStatsJob.perform_now(repo.id, copy_from_repo_id: @grit.id)
  end

  test "should copy language stats from the parent" do
    user = create(:user)
    @grit.analyze_languages

    fork = create(:fork_repository, forker: user, fork_repo: @grit)

    RepositoryCopyLanguageStatsJob.perform_now(fork.id, copy_from_repo_id: @grit.id)

    assert_equal @grit.language_breakdown, fork.language_breakdown
  end
end
