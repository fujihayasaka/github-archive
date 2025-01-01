# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDiscussionsRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_discussions_repository_deleted"
    @schema = "github.repositories.v1.Deleted"

    @org_discussion_config = create(:organization_discussion_config)
    @repo = @org_discussion_config.repository
  end

  test "removes org discussion config when repo deleted" do
    message = { repository_id: @repo.id }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    assert_equal 0, OrganizationDiscussionConfig.where(repository_id: @repo.id).count
  end

  test "is triggered when repo deleted" do
    perform_enqueued_hydro_jobs(only: [HydroDiscussionsRepositoryDeletedJob], allowed_primary_query_count: 3) do
      @repo.remove(@repo.owner, synchronous: true)
    end

    assert_equal 0, OrganizationDiscussionConfig.where(repository_id: @repo.id).count
  end
end
