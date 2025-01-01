# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryVisibilityChangedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @queue = HydroRepositoryVisibilityChangedJob.queue_name
      @schema = "github.repositories.v1.VisibilityChanged"
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
      @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(true)
    end

    context "#perform" do
      test "updates data on repo visibility changed event" do
        refute @soa_repo.private?

        expected_event_time = 1.day.ago
        Timecop.freeze(expected_event_time) do
          assert_query_counts(2) do
            perform_hydro_message_job({
              repository_id: @repo.id,
              old_visibility: :PUBLIC,
              new_visibility: :PRIVATE
            }, schema: @schema, queue: @queue)
          end
        end

        assert @soa_repo.reload.private?
        assert_equal expected_event_time.to_i, @soa_repo.event_time&.to_i
        assert_dogstats_increment 1, "security_overview_analytics.event.repository_visibility_changed.processed"
      end

      test "does nothing if repository owner validation fails" do
        TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(false)
        refute @soa_repo.private?

        assert_query_counts(1) do
          perform_hydro_message_job({
            repository_id: @repo.id,
            old_visibility: :PUBLIC,
            new_visibility: :PRIVATE
          }, schema: @schema, queue: @queue)
        end

        refute @soa_repo.reload.private?
        assert_dogstats_increment 1, "security_overview_analytics.event.repository_visibility_changed.skipped"
      end

      test "does not throw if data record does not already exist" do
        repo_id = @soa_repo.repository_id
        @soa_repo.destroy!
        refute Repository.find_by(repository_id: repo_id)

        assert_query_counts(2) do
          assert_nothing_raised do
            perform_hydro_message_job({
              repository_id: repo_id,
              old_visibility: :PUBLIC,
              new_visibility: :PRIVATE
            }, schema: @schema, queue: @queue)
          end
        end

        refute Repository.find_by(repository_id: repo_id)
      end

      test "updates updated_at column" do
        assert_changes(
          -> { @soa_repo.reload.updated_at }
        ) do
          assert_query_counts(2) do
            perform_hydro_message_job({
              repository_id: @repo.id,
              old_visibility: :PUBLIC,
              new_visibility: :PRIVATE
            }, schema: @schema, queue: @queue)
          end
        end
      end
    end
  end
end
