# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroCorrectStargazersRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_correct_stargazers_repository_transferred"
    @schema = "github.repositories.v1.Transferred"
    @repo = create(:repository)
  end

  test "should correct stars" do
    # this job only uses the repository
    message = {
      repository_id: @repo.id,
    }

    # checking the actual logic here would require performing the transfer, so stub it instead
    HydroCorrectStargazersRepositoryTransferredJob.any_instance.expects(:correct_stargazers).once

    perform_hydro_message_job(message, schema: @schema, queue: @queue)
  end


  test "stars are removed when transferring between orgs and some users no longer have access" do
    org_access = create(:organization)
    org_no_access = create(:organization)
    repo = create(:private_repository, owner: org_access)
    user = create(:user)
    user2 = create(:user)

    org_access.add_member(user)
    org_access.add_admin(user2)
    org_no_access.add_admin(user2)

    Stars.domain.star_repository(repository: repo, user: user)

    assert repo.readable_by?(user)
    assert Stars.domain.repo_starred_by_user?(repo.id, user.id)

    perform_enqueued_hydro_jobs(only: [HydroCorrectStargazersRepositoryTransferredJob], allowed_primary_query_count: 24) do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        repo.transfer_ownership_to(org_no_access, actor: user2)
      end
    end

    refute repo.readable_by?(user)
    refute Stars.domain.reset_caches.repo_starred_by_user?(repo.id, user.id)
  end
end
