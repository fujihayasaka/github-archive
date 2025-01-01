# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class HandlePrebuildsWhenRepoDeletedJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  test "Does not queue delete prebuild templates for repo job if repo not deleted" do
    repo = create(:repository, active: true, from_example: :simple)

    Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).never

    Codespaces::HandlePrebuildsWhenRepoDeletedJob.perform_now(repository_id: repo.id)
  end

  test "Queues delete prebuild templates for repo job if repo soft deleted" do
    # soft deleted
    repo = create(:repository, :soft_deleted, from_example: :simple)

    assert repo.deleted?

    Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(repository_id: repo.id)

    Codespaces::HandlePrebuildsWhenRepoDeletedJob.perform_now(repository_id: repo.id)
  end

  test "Queues delete prebuild templates for repo job if repo is hard deleted" do
    repo_id = 4

    Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(repository_id: repo_id)

    Codespaces::HandlePrebuildsWhenRepoDeletedJob.perform_now(repository_id: repo_id)
  end
end unless GitHub.enterprise?
