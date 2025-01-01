# typed: true
# frozen_string_literal: true

module Billing::SharedStorage
  class RebuildAggregationFromEvents
    attr_reader :owner, :repository_id
    def initialize(owner:, repository_id:)
      @owner = owner
      @repository_id = repository_id

      raise ArgumentError, "owner is required" unless owner
      raise ArgumentError, "owner must be a User" unless owner.is_a?(User)
      raise ArgumentError, "repository_id is required" unless repository_id
      @restraint = GitHub::Restraint.new
    end

    def perform
      restraint.lock!(lock_key, _concurrency = 1, _ttl = 5.minutes) do
        perform_without_lock
      end
    end

    def perform_without_lock
      current_usage = Billing::SharedStorage::CurrentUsage.find_by(
        owner_id: owner.id,
        repository_id: repository_id,
      )

      return unless current_usage
      current_usage.rebuild_from_events!
    end

    private

    attr_reader :restraint

    def lock_key
      "shared-storage/artifact-event-aggregator/#{owner.id}"
    end
  end
end
