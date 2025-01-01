# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroGenerateHookshotPayloadsRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HookIntegrationTestHelper

  setup do
    @queue = "hydro_generate_hookshot_payloads_repository_deleted"
    @schema = "github.repositories.v1.Deleted"
  end

  test "generate hookshot payloads when repository is deleted" do
    user = create :user, :zuora, plan: "pro"
    repo = create :private_repository, :soft_deleted, owner: user
    other_repo_hook = create :hook, :web, installation_target: repo, events: %w(*)

    deliveries = subscribe_to_hook_delivery "repository"

    message = { repository_id: repo.id, actor_id: user.id }

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob, EnqueueToHookshotJob]) do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end

    assert_equal 1, deliveries.count
  end
end
