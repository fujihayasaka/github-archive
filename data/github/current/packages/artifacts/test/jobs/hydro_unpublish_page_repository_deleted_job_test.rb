# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroUnpublishPageRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_unpublish_page_repository_deleted"
    @schema = "github.repositories.v1.Deleted"

    @repo = create(:repository)
  end

  test "unpublish page when repository is deleted" do
    GitHub.flipper[:pages_soft_deletion].disable
    page = create(:page, repository: @repo)

    refute_nil @repo.reload.page

    orchestration = RepositoryOrchestration.delete(@repo, actor: User.ghost)
    orchestration.execute(synchronous: true)

    perform_enqueued_jobs(only: [HydroUnpublishPageRepositoryDeletedJob]) do
      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)
    end

    assert_nil @repo.reload.page
  end
end
