# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class ArtifactEventTest < GitHub::TestCase
    context "validations" do
      test "requires repository_id to be positive" do
        invalid_artifact_events = [
          ArtifactEvent.new(owner_id: 1, repository_id: 0, size_in_bytes: 1),
          ArtifactEvent.new(owner_id: 1, repository_id: -1, size_in_bytes: 1)
        ]

        valid_artifact_event = ArtifactEvent.new(owner_id: 1, repository_id: 1, size_in_bytes: 1)

        invalid_artifact_events.each do |invalid_artifact_event|
          refute invalid_artifact_event.valid?
          assert_equal ["must be greater than 0"], invalid_artifact_event.errors[:repository_id]
        end

        assert valid_artifact_event.valid?
      end

      test "allows nil repository_id" do
        valid_artifact_event = ArtifactEvent.new(owner_id: 1, repository_id: 1, size_in_bytes: 1)
        assert valid_artifact_event.valid?
      end
    end

    context "callbacks" do
      test "prepares shared storage after create on add event" do
        assert_difference(-> { CurrentUsage.count }, 1) do
          perform_enqueued_jobs(only: [::Billing::SharedStorage::PrepareSharedStorageJob]) do
            create(:shared_storage_artifact_event, :add_event, size_in_bytes: 10)
          end
        end
      end

      test "sets the right shared storage attributes" do
        org = create(:enterprise_linked_organization)
        repo = create(:repository, owner: org)

        assert_difference(-> { CurrentUsage.count }, 1) do
          perform_enqueued_jobs(only: [::Billing::SharedStorage::PrepareSharedStorageJob]) do
            create(:shared_storage_artifact_event, :add_event, :private_visibility, size_in_bytes: 10, repository: repo)
          end
        end

        current_usage = CurrentUsage.last
        current_usage = T.must(current_usage)
        assert_equal org, current_usage.owner
        assert_equal org.business, current_usage.billable_owner
        assert_equal repo, current_usage.repository
        assert_equal "private", current_usage.repository_visibility
        assert_equal 0, current_usage.aggregate_size_in_bytes
      end

      test "does not prepare shared storage after update of any events" do
        events = perform_enqueued_jobs(only: [::Billing::SharedStorage::PrepareSharedStorageJob]) do
          [
            create(:shared_storage_artifact_event, :add_event, size_in_bytes: 10),
            create(:shared_storage_artifact_event, :remove_event, size_in_bytes: 10),
            create(:shared_storage_artifact_event, :unknown_event, size_in_bytes: 10)
          ]
        end

        CurrentUsage.destroy_all

        assert_no_difference(-> { CurrentUsage.count }) do
          perform_enqueued_jobs(only: [::Billing::SharedStorage::PrepareSharedStorageJob]) do
            events.each do |event|
              event.update!(size_in_bytes: 20)
            end
          end
        end
      end

      test "does not prepare shared storage after create on remove or unknown event" do
        assert_no_difference(-> { CurrentUsage.count }) do
          perform_enqueued_jobs(only: [::Billing::SharedStorage::PrepareSharedStorageJob]) do
            create(:shared_storage_artifact_event, :remove_event, size_in_bytes: 10)
            create(:shared_storage_artifact_event, :unknown_event, size_in_bytes: 10)
          end
        end
      end
    end

    context ".sum_bytes" do
      test "adds 'add events' and substracts 'remove events'" do
        create(:shared_storage_artifact_event, :add_event, size_in_bytes: 10)
        create(:shared_storage_artifact_event, :add_event, size_in_bytes: 20)
        create(:shared_storage_artifact_event, :remove_event, size_in_bytes: 5)

        assert_equal 25, ArtifactEvent.sum_bytes
      end

      test "returns 0 if there are no events" do
        assert_equal 0, ArtifactEvent.sum_bytes
      end
    end

    context ".upcoming_actions_expirations_by_repo_and_effective_at" do
      test "sum size_in_bytes by repo_id and effective_at for actions source" do
        repository = create(:repository)

        # Use system's local timezone since upcoming_actions_expirations_by_repo_and_effective_at casts to date
        # using a database cast and the database is always storing in localtime
        one_hour_in_the_future = 1.hour.from_now.localtime

        create(:shared_storage_artifact_event, :remove_event, :actions_source,
               size_in_bytes: 10,
               repository: repository,
               effective_at: one_hour_in_the_future)
        create(:shared_storage_artifact_event, :remove_event, :actions_source,
               size_in_bytes: 20,
               repository: repository,
               effective_at: one_hour_in_the_future)

        # Calculate tomorrow based on one_hour_in_the_future, not Time.now, since we
        # want the two timestamps to appear on different dates.
        tomorrow = one_hour_in_the_future.tomorrow
        create(:shared_storage_artifact_event, :remove_event, :actions_source,
               size_in_bytes: 100,
               repository: repository,
               effective_at: tomorrow)

        # Should not count add events
        create(:shared_storage_artifact_event, :add_event, :actions_source,
               size_in_bytes: 20,
               repository: repository,
               effective_at: one_hour_in_the_future)

        expected_result = {
          [repository.id, one_hour_in_the_future.to_date] => 30,
          [repository.id, tomorrow.to_date] => 100
        }
        assert_equal expected_result, ArtifactEvent.upcoming_actions_expirations_by_repo_and_effective_at(repository.owner_id)
      end

      test "returns empty hash if no upcoming_actions_expirations_by_repo_and_effective_at" do
        assert_equal Hash.new, ArtifactEvent.upcoming_actions_expirations_by_repo_and_effective_at(1)
      end
    end

    context ".billable_events_by_repo_and_source" do
      test "returns billable events by repo, source and aggregation_id IS NOT NULL" do
        repository = create(:repository)

        Timecop.freeze(Time.now - 1.hour) do
          # actions source
          create(:shared_storage_artifact_event, :add_event, :actions_source,
                 size_in_bytes: 10,
                 repository: repository)
          create(:shared_storage_artifact_event, :add_event, :actions_source,
                 size_in_bytes: 20,
                 repository: repository)
          create(:shared_storage_artifact_event, :remove_event, :actions_source,
                 size_in_bytes: 5,
                 repository: repository)

          # gpr source
          create(:shared_storage_artifact_event, :add_event, :gpr_source,
                 size_in_bytes: 20,
                 repository: repository)
          create(:shared_storage_artifact_event, :remove_event, :gpr_source,
                 size_in_bytes: 5,
                 repository: repository)

          # gpr source with aggregation_id
          create(:shared_storage_artifact_event, :add_event, :gpr_source,
                  size_in_bytes: 20,
                  repository: repository,
                  aggregation_id: 123)
        end

        # adds "add events" and subtracts "remove events"
        expected_result = {
          [repository.id, "actions", 0] => 25,
          [repository.id, "gpr", 0] => 15,
          [repository.id, "gpr", 1] => 20
        }
        assert_equal expected_result, ArtifactEvent.billable_events_by_repo_and_source(repository.owner_id)
      end

      test "returns empty hash if no billable_events_by_repo_and_source" do
        assert_equal Hash.new, ArtifactEvent.billable_events_by_repo_and_source(1)
      end
    end

    context ".container_registry_billable_events_by_repo" do
      test "returns billable events by repo for ghcr source" do
        repository = create(:repository)
        Timecop.freeze(Time.now - 1.hour) do
          create(:shared_storage_artifact_event, :add_event, :ghcr_source,
                 size_in_bytes: 10,
                 repository: repository)
          create(:shared_storage_artifact_event, :add_event, :ghcr_source,
                 size_in_bytes: 20,
                 repository: repository)
          create(:shared_storage_artifact_event, :remove_event, :ghcr_source,
                 size_in_bytes: 5,
                 repository: repository)
        end

        # adds "add events" and subtracts "remove events"
        assert_equal 25, ArtifactEvent.container_registry_billable_events_by_repo(owner_id: repository.owner_id)
      end
    end

    context "#aggregated?" do
      test "returns true if aggregation_id IS NOT NULL" do
        event = create(:shared_storage_artifact_event, aggregation_id: 1)
        assert event.aggregated?, "Expected event to be aggregated"
      end

      test "returns false if aggregation_id IS NULL" do
        event = create(:shared_storage_artifact_event, aggregation_id: nil)
        assert_not event.aggregated?, "Expected event to NOT be aggregated"
      end
    end
  end
end if GitHub.billing_enabled?
