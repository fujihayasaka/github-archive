# typed: true
# frozen_string_literal: true

module Billing::SharedStorage
  class ArtifactEvent < ApplicationRecord::Domain::Billing
    self.table_name = "shared_storage_artifact_events"

    after_create :prepare_shared_storage, if: :add_event?

    enum :source, {
      unknown: "unknown",
      actions: "actions",
      gpr: "gpr",
      ghcr: "ghcr",
      packages_v2: "packages_v2",
    }, suffix: true

    enum :repository_visibility, {
      unknown: "unknown",
      public: "public",
      private: "private",
    }, suffix: :visibility

    enum :event_type, {
      unknown: "unknown",
      add: "add",
      remove: "remove",
    }, suffix: :event

    belongs_to :owner, class_name: "User", optional: true
    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain

    validates :owner_id, presence: true
    validates :repository_id, numericality: { greater_than: 0, allow_nil: true }
    validates :size_in_bytes, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :sum_bytes, -> {
      sum(<<~SQL)
        CASE event_type
        WHEN 'add' then size_in_bytes
        WHEN 'remove' then -1 * size_in_bytes
        ELSE 0
        END
      SQL
    }

    def self.upcoming_actions_expirations_by_repo_and_effective_at(owner_id)
      actions_source
        .remove_event
        .where("effective_at > ?", ::GitHub::Billing.now)
        .where(owner_id: owner_id)
        .group(["repository_id", "CAST(effective_at AS DATE)"])
        .sum(:size_in_bytes)
    end

    def self.billable_events_by_repo_and_source(owner_id, effective_at = ::GitHub::Billing.now)
      where("effective_at <= ?", effective_at)
      .where(owner_id: owner_id)
      .group(["repository_id", "source", "aggregation_id IS NOT NULL"])
      .sum_bytes
    end

    def self.container_registry_billable_events_by_repo(owner_id:, effective_at: ::GitHub::Billing.now)
      where("effective_at <= ?", effective_at)
      .where(owner_id: owner_id)
      .ghcr_source
      .sum_bytes
    end

    # We no longer associate aggregations with events, but we still want to provide a way to identify
    # whether an event has been aggregated.
    def aggregated?
      aggregation_id.present?
    end

    def prepare_shared_storage
      billable_owner_attributes = ActiveRecord::Base.connected_to(role: :reading) do
        ::Billing::MeteredBillingBillableOwnerDesignator.attributes_for(owner)
      end

      PrepareSharedStorageJob.perform_later(
        **T.unsafe({
          owner_id: owner_id,
          repository_id: repository_id,
          repository_visibility: repository_visibility,
          **billable_owner_attributes,
        })
      )
    end
  end
end
