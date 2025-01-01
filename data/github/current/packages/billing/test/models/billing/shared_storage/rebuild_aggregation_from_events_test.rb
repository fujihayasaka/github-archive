# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class RebuildAggregationFromEventsTest < GitHub::TestCase
    include GitHub::LoggerHelper

    fixtures do
      @repository = create(:repository)
      @owner = @repository.owner
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: 1)
      create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: 1)
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 10.megabytes, effective_at: 1.day.from_now)
    end

    context "validations" do
      test "requires an owner" do
        assert_raises(ArgumentError, "owner is required") do
          Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: nil, repository_id: @repository.id)
        end
      end

      test "require the owner to be a User" do
        assert_raises(ArgumentError, "owner must be a User") do
          Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: Object.new, repository_id: @repository.id)
        end
      end

      test "requires a repository_id" do
        assert_raises(ArgumentError, "owner must be a User") do
          Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: @owner, repository_id: nil)
        end
      end
    end

    context "Billing::SharedStorage::CurrentUsage" do
      test "fixes a mismatched aggregation" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )
        rebuilder = Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: @owner, repository_id: @repository.id)
        rebuilder.perform

        assert_equal(50.megabytes, agg.reload.aggregate_size_in_bytes)
      end

      test "treats negative sums as 0" do
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 150.megabytes, effective_at: 2.days.ago, aggregation_id: 1)
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )

        rebuilder = Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: @owner, repository_id: @repository.id)
        rebuilder.perform

        assert_equal(0.megabytes, agg.reload.aggregate_size_in_bytes)
      end

      test "logs the mismatch" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )

        expected_log = {
          Body: "SharedStorage size mismatch",
          "gh.billing.current_usage.owner.id": @owner.id,
          "gh.repo.id": @repository.id,
          "code.namespace": "Billing::SharedStorage::CurrentUsage",
          "gh.billing.current_usage.id": agg.id,
          "gh.billing.current_usage.old_size": 1.megabytes,
          "gh.billing.current_usage.new_size": 50.megabytes
        }

        assert_logged(**expected_log) do
          rebuilder = Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: @owner, repository_id: @repository.id)
          rebuilder.perform
        end
      end

      test "No updates on match" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 50.megabytes,
          effective_at: Time.current
        )

        assert_no_changes -> { agg.reload.updated_at } do
          rebuilder = Billing::SharedStorage::RebuildAggregationFromEvents.new(owner: @owner, repository_id: @repository.id)
          rebuilder.perform
        end
      end
    end
  end
end if GitHub.billing_enabled?
