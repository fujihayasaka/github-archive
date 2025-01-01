# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDeletePullRequestRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_delete_pull_request_repository_deleted"
    @schema = "github.repositories.v1.Deleted"
  end

  test "deletes installations when repository is deleted" do
    user1 = create(:user)
    forkable_repo = create(:repository, name: "test-repo", owner: user1, from_example: :pull_request_source)

    user2 = create(:user)
    forked_repo = create(:repository, name: "test-repo", owner: user2, from_example: :pull_request_source)
    pr = create(:pull_request, repository: forkable_repo, base_repository: forkable_repo, head_repository: forked_repo, head_ref: "master-merged-topic")

    PullRequest.any_instance.expects(:maintain_tracking_ref_with_retries).with(pr.safe_user)
    assert_equal "open", pr.issue.state

    orchestration = RepositoryOrchestration.delete(forked_repo, actor: User.ghost)
    orchestration.execute(synchronous: true)

    perform_enqueued_jobs(only: [HydroDeletePullRequestRepositoryDeletedJob]) do
      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)
    end

    assert_equal "closed", pr.issue.reload.state
  end
end
