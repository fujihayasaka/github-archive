# typed: true
# frozen_string_literal: true

require "github/bound_retry"

module Billing::SharedStorage
  class ArtifactEventAggregationFanout
    attr_reader :cutoff, :fan_index, :fan_total

    RANDOM_SPLAY = 3.minutes

    def initialize(cutoff:, fan_index: nil, fan_total: nil)
      @cutoff = cutoff
      @fan_index = fan_index
      @fan_total = fan_total || 1

      @restraint = GitHub::Restraint.new
      @use_jitter = FeatureFlag.vexi.enabled_or_raise?(:shared_storage_aggregation_job_use_jitter) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def perform
      restraint.lock!(lock_key, _concurrency = 1, _ttl = 5.minutes) do
        perform_without_lock
      end
    end

    def perform_without_lock
      GitHub.dogstats.count("billing.shared_storage.users_selected", owner_ids.count)

      owner_ids.each do |owner_id|
        if @use_jitter
          # create a jitter/splay that will randomize when the jobs are scheduled
          # base the jitter off of the fan_index so that the same owner_id is still queued roughly around the same time
          # fan_index = 0: close to the top of the hour
          # fan_index = fan_total-1: close to the bottom of the hour
          #
          # keep this value bounded so it doesn't exceed 40 minutes, so it has enough time to complete before the next run
          # in case fan_total is changed beyond 40
          jitter = [((fan_index.to_f / fan_total.to_f) * 30).minutes + rand(RANDOM_SPLAY.to_i), 40.minutes].min
          AggregationJob.set(wait: jitter).perform_later(cutoff: cutoff, owner_id: owner_id)
        else
          AggregationJob.perform_later(cutoff: cutoff, owner_id: owner_id)
        end
      end
    end

    private

    attr_reader :restraint

    def owner_ids
      return @_owner_ids if defined?(@_owner_ids)

      aggregate_query = Billing::SharedStorage::CurrentUsage.select(:owner_id).distinct

      if fan_index
        aggregate_query = aggregate_query.where("owner_id % ? = ?", fan_total, fan_index)
      end

      @_owner_ids = ActiveRecord::Base.connected_to(role: :reading) do
        aggregate_query.pluck(:owner_id)
      end
    end

    def lock_key
      if fan_index
        "shared-storage/artifact-event-aggregation-fanout-#{fan_index}"
      else
        "shared-storage/artifact-event-aggregation-fanout"
      end
    end
  end
end
