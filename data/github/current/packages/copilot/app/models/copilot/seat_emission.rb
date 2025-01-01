# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatEmission < ApplicationRecord::Copilot
    extend T::Sig
    include ::Instrumentation::Model

    REQUIRED_EMISSION_KEYS = T.let(%w[usage_uuid product_name product_sku_name usage_at quantity account_id].freeze, T::Array[String])

    self.table_name = "copilot_seat_emissions"
    self.strict_loading_by_default = true

    belongs_to :owner, polymorphic: true, strict_loading: false

    validates :emission, presence: true
    validates :occurred_at, presence: true
    validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :unique_id, presence: true

    validate :emission_duration
    validate :emission_format

    before_validation :set_owner_type

    scope :for_owner, ->(owner) do
      where(owner_type: owner.class.name, owner_id: owner.id)
    end

    # This checks whether we can emit for an enterprise.
    # We can emit for an enterprise if:
    # - they are not in the copilot_for_business_free flag (this flag is used for GH, MSFT etc)
    # - they are billable
    # - they haven't emitted today
    #
    # Spammy or suspended businesses, or those that can't be billed have their and their organization's
    # Copilot seats, seat assignments, and configs destroyed, if allow_cleanup: true is passed
    sig { params(enterprise: ::Business, allow_cleanup: T::Boolean).returns(T::Boolean) }
    def self.enterprise_can_emit?(enterprise, allow_cleanup: false)
      copilot_business = Copilot::Business.new(enterprise)

      # if they are in the copilot_for_business_free flag, we don't emit for them at all
      if copilot_business.copilot_for_business_free?
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]}"])
        return false
      end

      if copilot_business.spammy?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason) if allow_cleanup

        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
        GitHub.logger.info(
          "Enterprise is spammy",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )
        return false
      end

      if copilot_business.suspended?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason) if allow_cleanup

        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
        GitHub.logger.info(
          "Enterprise is suspended",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )
        return false
      end

      if !copilot_business.copilot_billable?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
        Copilot::Helpers.chatterbox_say("Copilot::SeatEmission for enterprise #{enterprise.id} is not billable!")
        GitHub.logger.info(
          "Enterprise is not billable",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )
      end

      if copilot_business.copilot_disabled?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason) if allow_cleanup

        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
        GitHub.logger.info(
          "Copilot is disabled for this enterprise",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )

        return false
      end

      # okay, we're at the place where we can emit for them, let's check if they have emitted today
      today = Date.current

      if Copilot::SeatEmission.for_owner(enterprise).where(occurred_at: today.beginning_of_day..today.end_of_day).exists?
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{COPILOT_SEAT_EMISSION_ERRORS[:too_soon]}"])
        false
      else
        GitHub.dogstats.increment("copilot.seat_emission.can_emit")
        true
      end
    end

    # This checks whether we can emit for an organization.
    # We can emit for an organization if:
    # - they are not in the copilot_for_business_free flag (this flag is used for GH, MSFT etc)
    # - they are not on a Copilot Business trial
    # - they are not spammy
    # - they or their business have enabled copilot in their settings
    # - they haven't emitted today
    # - they have a valid billing method on file
    # Pass `allow_cleanup: true` if you want spammy/unbillable/etc orgs to have their seats cleaned up
    sig { params(organization: ::Organization, allow_cleanup: T::Boolean).returns(T::Boolean) }
    def self.can_emit?(organization, allow_cleanup: false)
      copilot_organization = Copilot::Organization.new(organization)

      # if they are in the copilot_for_business_free flag, we don't emit for them at all
      if copilot_organization.copilot_for_business_free?
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]}"])
        return false
      end

      # if they are on a Copilot Business trial, don't emit for them
      if copilot_organization.on_free_copilot_business_trial?
        # We don't use the COPILOT_SEAT_EMISSION_ERRORS hash here because the values are different between the dogstats tag
        # and the instrumented data we send to hydro
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:business_trial"])
        return false
      end

      # they or their business need to have enabled copilot in their settings
      # typically, i hate doing `if not` but i think it reads better here with the others
      if !copilot_organization.has_copilot_for_business?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        # we're gonna queue up another job to handle this
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
        return false
      end

      if copilot_organization.suspended?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
        return false
      end

      if copilot_organization.spammy?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]

        # Spammy businesses making it this far is not ideal but we'll just clean them up
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
        return false
      end

      if !copilot_organization.copilot_billable?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])

        if allow_cleanup
          Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable])
          GitHub.logger.info("Cleaning organization that failed copilot_billable?", {
            "gh.copilot.organization.id" => organization.id,
            "gh.copilot.reason" => reason,
          })
        end

        return false
      end

      # okay, we're at the place where we can emit for them, let's check if they have emitted today
      today = Date.current

      if Copilot::SeatEmission.for_owner(organization).where(occurred_at: today.beginning_of_day..today.end_of_day).exists?
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{COPILOT_SEAT_EMISSION_ERRORS[:too_soon]}"])
        false
      else
        GitHub.dogstats.increment("copilot.seat_emission.can_emit")
        true
      end
    end

    sig { void }
    def set_owner_type
      if owner.present?
        self.owner_type = owner.class.name
      else
        # default to organization
        self.owner_type = "Organization"
      end
    end

    # we can only emit once per day. - let's see if there is already one for today
    sig { void }
    def emission_duration
      if occurred_at.present? && owner.present?
        today = occurred_at.to_date

        if Copilot::SeatEmission.for_owner(owner).where(occurred_at: today.beginning_of_day..today.end_of_day).exists?
          errors.add(:occurred_at, "already have an emission for this date")
        end
      end
    end

    sig { void }
    def emission_format
      unless emission.is_a?(Hash)
        errors.add(:emission, "must be a hash")
        return
      end

      unless emission.key?("meuse_payload") || emission.key?("billing_platform_payload")
        errors.add(:emission, "must have a meuse_payload or billing_platform_payload key")
        return
      end

      platform_payload_key = emission.key?("meuse_payload") ? "meuse_payload" : "billing_platform_payload"
      missing_keys = REQUIRED_EMISSION_KEYS - emission[platform_payload_key].keys
      missing_keys.each do |key|
        errors.add(:emission, "must have a #{key} key")
      end
    end

    sig { returns(String) }
    def usage_uuid
      emission.dig("meuse_payload", "usage_uuid").to_s || emission.dig("billing_platform_payload", "usage_uuid").to_s
    end

    sig { returns(String) }
    def source_uri
      emission.dig("meuse_payload", "source_uri").to_s || emission.dig("billing_platform_payload", "source_uri").to_s
    end

    sig { returns(Time) }
    def usage_at
      usage_at = emission.dig("meuse_payload", "usage_at").to_s || emission.dig("billing_platform_payload", "usage_at").to_s
      Time.parse(usage_at)
    end
  end
end
