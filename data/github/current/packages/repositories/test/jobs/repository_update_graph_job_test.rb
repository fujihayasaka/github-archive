# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUpdateGraphJobTest < GitHub::TestCase
  include CommitTestHelper

  fixtures do
    @committer = create(:user)
    @repo = create(:repository, owner: @committer)
  end

  test "ignores GitHub::DGit::UnroutedError" do
    GitHub::RepoGraph.stubs(:update).raises(GitHub::DGit::UnroutedError)

    # Just call it to make sure it doesn't raise.
    RepositoryUpdateGraphJob.perform_now(@repo.id, "contributors")
  end

  test "only one job of each type is enqueued concurrently" do
    assert_enqueued_jobs 1, queue: "graphs" do
      3.times { RepositoryUpdateGraphJob.perform_later(@repo.id, "contributors") }
    end
  end
end
