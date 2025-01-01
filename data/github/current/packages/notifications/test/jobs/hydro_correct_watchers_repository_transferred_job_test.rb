# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroCorrectWatchersRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_correct_watchers_repository_transferred"
    @schema = "github.repositories.v1.Transferred"
    @repo = create(:repository)
  end

  test "should correct watchers" do
    # this job only uses the repository
    message = {
      repository_id: @repo.id,
    }

    # checking the actual logic here would require performing the transfer, so stub it instead
    Repository.any_instance.expects(:correct_watchers).once

    perform_hydro_message_job(message, schema: @schema, queue: @queue)
  end
end
