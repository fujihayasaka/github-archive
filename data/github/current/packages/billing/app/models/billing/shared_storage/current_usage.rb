# typed: strict
# frozen_string_literal: true

module Billing::SharedStorage
  class CurrentUsage < ApplicationRecord::Domain::Billing
    extend T::Sig
    self.table_name = "shared_storage_usage"

    # Sometimes the User/Organization is deleted while we still have unprocessed events
    # In that case, let's not leave the events with a null aggregation_id
    # to be picked up and set down again in the next hourly run
    ORPHANED_EVENT_AGGREGATION_ID = 0

    # We used to have separate record for every Aggregation hour
    # At that time we'd store that hour's record id on the ArtifactEvent
    # Now that we just have a single CurrentUsage record
    # We'll mark the event as aggregated by setting a static ID for now so
    # That we don't need to change db indexes
    EVENT_AGGREGATION_ID = 1

    EVENT_UPDATE_BATCH_SIZE = 1000

    LARGE_EVENT_WINDOW_HOURS = 6
    MAX_WINDOWS_TO_AGGREGATE = 24
    MAX_REPLICATION_DELAY_WAIT_SECONDS = 5

    enum :repository_visibility, {
      unknown: "unknown",
      public: "public",
      private: "private",
    }, suffix: :visibility

    belongs_to :owner, class_name: "User"
    belongs_to :repository
    belongs_to :billable_owner, polymorphic: true

    validates :owner_id, presence: true
    validates :repository_id, presence: true
    validates :aggregate_size_in_bytes, presence: true

    scope :for_reporting, -> (billable_owner:, owner_id: nil, repository_visibility: "private") do
      query = where(repository_visibility: repository_visibility, billable_owner: billable_owner)
      if owner_id.present?
        query = query.where(owner_id: owner_id)
      end
      query
    end

    # Public: Transform the usage record into a hash ready to be sent to Meuse
    sig { params(quantity: ::Billing::Types::Numeric).returns(T::Hash[Symbol, T.untyped]) }
    def to_meuse(quantity: aggregate_size_in_bytes)
      custom_fields = {}
      custom_fields["repository.id"] = repository_id

      {
        product_name: "shared_storage",
        product_sku_name: "default",
        quantity: quantity,
        account_id: owner_id,
        usage_at: effective_at,
        usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid(guid),
        source_uri: guid,
        custom_fields: custom_fields,
      }
    end

    # Public: Returns whether this record should be sent to Meuse
    sig { returns(T::Boolean) }
    def reportable_to_meuse?
      private_visibility? &&
        aggregate_size_in_bytes.positive?
    end

    sig { void }
    def rebuild_from_events!
      with_lock do
        sum_of_event_bytes = [ArtifactEvent
            .where(owner_id: owner_id)
            .where(repository_id: repository_id_for_events)
            .where(effective_at: ..effective_at)
            .where.not(aggregation_id: nil)
            .sum_bytes, 0].max

        if sum_of_event_bytes != aggregate_size_in_bytes
          GitHub.logger.info(
            "SharedStorage size mismatch",
            "code.namespace" => self.class.name,
            "gh.billing.current_usage.owner.id" => owner_id,
            "gh.repo.id" => repository_id,
            "gh.billing.current_usage.id" => id,
            "gh.billing.current_usage.old_size" => aggregate_size_in_bytes,
            "gh.billing.current_usage.new_size" => sum_of_event_bytes
          )

          update!(aggregate_size_in_bytes: sum_of_event_bytes)
        end
      end
    end

    sig { void }
    def update_from_events!
      # Process events for fully completed hours
      max_cutoff = Time.current.beginning_of_hour

      usage_needs_updating = T.let(true, T::Boolean)
      windows_processed = 0

      # when feature flag is enabled, we will process up to 12 hours of events per published line item
      update_event_window = GitHub.flipper[:billing_large_event_windows].enabled? ? LARGE_EVENT_WINDOW_HOURS.hours : 1.hour

      # We want to release the lock after each loop so that an error doesn't
      # rollback all hours
      while usage_needs_updating
        with_lock do
          prior_effective_at = effective_at.beginning_of_hour
          # We stop updating effective_at once the object is destroyed so check for that
          # to make sure we don't get stuck in a loop
          if destroyed? || prior_effective_at + (update_event_window - 1.hour) >= max_cutoff || windows_processed >= MAX_WINDOWS_TO_AGGREGATE
            usage_needs_updating = false
          else
            update_from_events_through!(cutoff: prior_effective_at + update_event_window)
            windows_processed += 1
          end
        end
      end
    end

    sig { params(cutoff: Time, start: Time).void }
    def update_from_events_through!(cutoff:, start: effective_at.to_time.beginning_of_hour)
      cutoff = cutoff.beginning_of_hour
      return if cutoff <= effective_at

      unprocessed_events = if GitHub.flipper[:billing_artifact_use_replica].enabled?
        if GitHub.flipper[:billing_artifact_wait_for_replication].enabled?
          last_writes = DatabaseSelector::ReplicationState.current&.to_hash || Timestamp.from_time(Time.now)
          waited_secs = WaitForReplication.new(
            last_writes,
            max_wait_seconds: MAX_REPLICATION_DELAY_WAIT_SECONDS,
            job_name: "Billing::SharedStorage::AggregationJob"
          ).wait!
          GitHub.dogstats.count("billing.shared_storage.replication_wait_time", waited_secs)
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          ArtifactEvent
            .where(effective_at: ..cutoff)
            .where(owner_id: owner_id)
            .where(repository_id: repository_id_for_events)
            .where(aggregation_id: nil)
            .all
        end
      else
        ArtifactEvent
          .where(effective_at: ..cutoff)
          .where(owner_id: owner_id)
          .where(repository_id: repository_id_for_events)
          .where(aggregation_id: nil)
          .all
      end.to_a

      owner = ActiveRecord::Base.connected_to(role: :reading) do
        self.owner
      end

      if owner.nil?
        update_events_with_aggregation_id(
          events: unprocessed_events,
          aggregation_id: ORPHANED_EVENT_AGGREGATION_ID,
          cutoff: cutoff
        )
        self_destruct(reason: "missing_owner")
        return
      end

      if repository_id.positive? && unprocessed_events.empty?
        repository = ActiveRecord::Base.connected_to(role: :reading) do
          self.repository
        end

        if repository.nil?
          self_destruct(reason: "missing_repository")
          return
        end

        if repository.deleted?
          self_destruct(reason: "inactive_repository")
          return
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          repository.owner
        end

        if repository.owner != owner
          self_destruct(reason: "owner_mismatch")
          return
        end
      end

      new_size_in_bytes = [aggregate_size_in_bytes.to_i + size_delta_for(unprocessed_events), 0].max

      if new_size_in_bytes.positive? || unprocessed_events.any?
        ActiveRecord::Base.connected_to(role: :reading) do
          owner.billable_owner
        end

        self.class.transaction do
          update!(
            aggregate_size_in_bytes: new_size_in_bytes,
            effective_at: cutoff,
            repository_visibility: new_repository_visibility_for(unprocessed_events),
            billable_owner: owner.billable_owner,
          )
          update_events_with_aggregation_id(
            events: unprocessed_events,
            aggregation_id: EVENT_AGGREGATION_ID,
            cutoff: cutoff
          )

          GitHub.dogstats.increment("billing.shared_storage.repositories_aggregated")
          GitHub.dogstats.count("billing.shared_storage.events_aggregated", unprocessed_events.size)
          GitHub.dogstats.distribution("billing.shared_storage.events_aggregated_dist", unprocessed_events.size)
        end

        if reportable_to_meuse?
          window_end = [Time.current.beginning_of_hour, cutoff].min
          window_size_in_hours = (window_end - start) / 1.hour
          aggregate_byte_hours = aggregate_size_in_bytes * window_size_in_hours
          ActiveRecord::Base.connected_to(role: :reading) do
            GlobalInstrumenter.instrument("meuse.metered_usage", to_meuse(quantity: aggregate_byte_hours))
          end
        end
      else
        update!(effective_at: cutoff)
      end
    end

    private

    sig { returns(String) }
    def guid
      "#{to_global_id}-#{effective_at.to_i}"
    end

    sig { returns(T.any(Integer, T::Array[T.nilable(Integer)])) }
    def repository_id_for_events
      repository_id.to_i.positive? ? repository_id : [0, nil]
    end

    sig { params(events: T::Array[ArtifactEvent], aggregation_id: Integer, cutoff: Time).void }
    def update_events_with_aggregation_id(events:, aggregation_id:, cutoff:)
      # Avoid massive queries with unbounded list of ids
      events.map(&:id).each_slice(EVENT_UPDATE_BATCH_SIZE) do |ids|
        ArtifactEvent.where(id: ids).update_all(aggregation_id: aggregation_id, updated_at: cutoff)
      end
    end

    sig { params(reason: String).void }
    def self_destruct(reason:)
      GitHub.dogstats.increment(
        "billing.shared_storage.aggregate_repositories_skipped",
        tags: ["reason:#{reason}"],
      )
      destroy
    end

    sig { params(events: T::Array[ArtifactEvent]).returns(Integer) }
    def size_delta_for(events)
      events.sum do |event|
        case event.event_type
        when "add" then event.size_in_bytes
        when "remove" then -1 * event.size_in_bytes
        else 0
        end
      end
    end

    sig { params(events: T::Array[ArtifactEvent]).returns(T.nilable(T.any(Symbol, String))) }
    def new_repository_visibility_for(events)
      lookup_repository_visibility ||
      events.last&.repository_visibility ||
      repository_visibility
    end

    sig { returns(T.nilable(Symbol)) }
    def lookup_repository_visibility
      @current_repository_visibility ||= T.let(ActiveRecord::Base.connected_to(role: :reading) do
        repo = Repository.where(id: repository_id).select(:public).last

        if repo
          repo.public ? :public : :private
        end
      end, T.nilable(Symbol))
    end
  end
end
