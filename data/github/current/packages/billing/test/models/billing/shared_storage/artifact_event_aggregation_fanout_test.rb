# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class ArtifactEventAggregationFanoutTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @owner1 = create(:user, id: 100001)
      @owner2 = create(:user, id: 100002)
      @repo1 = create(:repository, owner: @owner1)
      @repo2 = create(:repository, owner: @owner2)
      @cutoff = Time.now.freeze
    end

    test "enqueues an AggregationJob for each user" do
      create(:shared_storage_current_usage, owner: @owner1, repository: @repo1)
      create(:shared_storage_current_usage, owner: @owner2, repository: @repo2)

      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: @repo1)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: @repo2)

      assert_enqueued_jobs(2, only: AggregationJob) do
        ArtifactEventAggregationFanout.new(cutoff: @cutoff).perform
      end
    end

    test "enqueues an AggregationJob for users within the fan if fan_index is set" do
      create(:shared_storage_current_usage, owner: @owner1, repository: @repo1)
      create(:shared_storage_current_usage, owner: @owner2, repository: @repo2)

      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: @repo1)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: @repo2)

      fan_total = 10
      fan_index = @owner1.id % fan_total
      # skips the event for owner2 since the id isn't part of fan_index: "fan_index"
      assert_enqueued_jobs(1, only: AggregationJob) do
        ArtifactEventAggregationFanout.new(cutoff: @cutoff, fan_index: fan_index, fan_total: fan_total).perform
      end
    end
  end
end if GitHub.billing_enabled?
