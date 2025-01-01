# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSponsorsRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_sponsors_repository_deleted"
    @schema = "github.repositories.v1.Deleted"
    @sponsorable = create(:organization)
    @repo = create(:repository, owner: @sponsorable)
    @listing = create(:sponsors_listing, sponsorable: @sponsorable)
    @listing.featured_items.create(featureable: @repo)
    @stafftools_metadata = @listing.stafftools_metadata
    @tier = create(:sponsors_tier, sponsors_listing: @listing)
  end

  test "updates stafftools metadata when last public non-forked repo is deleted" do
    skip unless GitHub.sponsors_enabled?

    assert_predicate @stafftools_metadata.reload, :has_public_non_fork_repository?

    # hide_repo needs to run in order for update_sponsors_listing_metadata_if_necessary to work
    orchestration = RepositoryOrchestration.delete(@repo, actor: User.ghost)
    orchestration.execute(synchronous: true)

    perform_enqueued_jobs(only: [NullifyDependentRecordsJob, DeleteDependentRecordsJob]) do
      perform_hydro_message_job(orchestration.build_hydro_event_message, schema: @schema, queue: @queue)
    end

    assert_nil @tier.reload.repository
    assert_predicate @listing.reload.featured_items, :empty?
    refute_predicate @stafftools_metadata.reload, :has_public_non_fork_repository?
  end
end
