# typed: true
# frozen_string_literal: true

module Billing::SharedStorage
  class ArtifactEventAggregator
    MAX_TRANSACTION_RETRY = 5

    attr_reader :cutoff, :owner_id

    def initialize(cutoff:, owner_id:)
      @cutoff = cutoff
      @owner_id = owner_id

      @restraint = GitHub::Restraint.new
    end

    def perform
      restraint.lock!(lock_key, _concurrency = 1, _ttl = 5.minutes) do
        perform_without_lock
      end
    end

    def perform_without_lock
      ##Used temporarily to be able to emit to both meuse and billing-platform
      return if billable_owner_migrated_to_billing_platform? && !GitHub.flipper[:actions_storage_usage_dual_emit_to_meuse_and_vnext].enabled?(owner&.billable_owner)
      return if skip_shared_storage_aggregation_for?(owner)

      owner_arg = if owner.present?
        { owner: owner }
      else
        { owner_id: owner_id }
      end

      event_repositories.each do |repository_id|
        usage = ActiveRecord::Base.connected_to(role: :reading) do
          usage_params = owner_arg.merge({ repository_id: repository_id.to_i })
          CurrentUsage.find_by(usage_params)
        end

        next if usage.nil?
        CurrentUsage.throttle_with_retry do
          usage.update_from_events!
        end
      end


      if owner
        notify_later_if_applicable
      end
    end

    private

    attr_reader :restraint

    def billable_owner_migrated_to_billing_platform?
      return false unless GitHub.flipper[:actions_storage_migration_skip].enabled?

      ActiveRecord::Base.connected_to(role: :reading) do
        owner&.billable_owner&.customer&.billing_platform_enabled_product&.actions? || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
      end
    end

    def skip_shared_storage_aggregation_for?(owner)
      GitHub.flipper[:skip_shared_storage_aggregation].enabled?(owner&.billable_owner) ||
      GitHub.flipper[:skip_shared_storage_aggregation].enabled?(owner)
    end

    def notify_later_if_applicable
      MeteredBillingThresholdNotifierJob.set(wait: 15.minutes).perform_later(
        owner_id: owner.id,
        product: ::Billing::Notifications::SHARED_STORAGE_PRODUCT,
      )
    end

    def owner
      @owner ||= ActiveRecord::Base.connected_to(role: :reading) do
        # Loads the user and billable_owner association while connected to the reading role
        User.find_by(id: owner_id).tap { |o| o&.billable_owner }
      end
    end

    def event_repositories
      return @event_repositories if defined?(@event_repositories)
      @event_repositories = ActiveRecord::Base.connected_to(role: :reading) do
        ArtifactEvent.where(owner_id: owner_id).select(:repository_id).distinct.pluck(:repository_id)
      end
    end

    def lock_key
      "shared-storage/artifact-event-aggregator/#{owner_id}"
    end
  end
end
