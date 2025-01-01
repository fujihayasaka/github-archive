#!/usr/bin/env ruby
# frozen_string_literal: true

module Ingest
  class ResetManifestsProcessor < Processor
    def initialize(name: "reset_manifests", debug: false)
      super
    end

    def metric_name
      "etl.reset_manifests"
    end

    def consume_message(message)
      # message is an instance of proto/hydro/schemas/github/dependencygraph/v1/reset_manifests_pb.rb containing:
      # - request_context: RequestContext
      # - actor: User
      # - repository: Repository
      # - owner: User
      # - action: ResetAction (REDETECT or CLEAR)
      # - trigger: ResetTrigger

      data = message.value.with_indifferent_access
      repo_id = data[:repository][:id]
      repo_actor = FeatureFlags::Actor::Repository.new(repo_id)
      action = data[:action]
      trigger = data[:trigger]

      # Skip processing if the action is not RESET_ACTION_CLEAR
      unless action == :RESET_ACTION_CLEAR
        increment_instrument("skipped", action, trigger)
        return
      end

      # Skip processing if the repository does not exist
      repository = Repository.find_by_github_repository_id(repo_id)
      unless repository.present?
        increment_instrument("repo_not_found", action, trigger)
        return
      end

      # Use the backfill queue for mass offboard (if enabled), otherwise use the normal queue
      if trigger == :RESET_TRIGGER_MASS_OFFBOARD
        is_backfill = true
        is_enqueued = ClearDependenciesBackfillJob.perform_later(repo_id, log_context: get_logging_context(message))
      else
        is_backfill = false
        is_enqueued = ClearDependenciesJob.perform_later(repo_id, log_context: get_logging_context(message))
      end

      increment_instrument(is_enqueued.nil? ? "failed" : "success", action, trigger, backfill: is_backfill, public: repository.public?)
    end

    def increment_instrument(result, action, trigger, backfill: nil, public: nil)
      Instrument.increment(
        metric_name,
        result: result,
        action: action,
        trigger: trigger,
        backfill: backfill,
        public: public
      )
    end

    def consume_debug_message(message)
      puts message.inspect
    end
  end
end
