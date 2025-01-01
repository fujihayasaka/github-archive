# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatEmission < ApplicationRecord::Copilot
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
    # Spammy or suspended businesses, or those that can't be billed have their Copilot seats, seat assignments,
    # and configs destroyed if they are not enrolled in the copilot_revokable_access
    # feature flag. If they are enrolled in that feature, we don't destroy their seats, but we do
    # revoke access to their seat assignments.
    #
    # This method is only called for standalone (non-GHEC enterprises)
    sig { params(enterprise: ::Business).returns(T::Boolean) }
    def self.enterprise_can_emit?(enterprise)
      copilot_business = Copilot::Business.new(enterprise)
      has_revokable_access = copilot_business.feature_enabled?(:copilot_revokable_access)
      billable_result = copilot_business.copilot_billable_result
      has_trade_restrictions = billable_result[:reason] == :has_any_trade_restrictions || billable_result[:reason] == :has_full_trade_restrictions

      # This is bad. We can't legally take this user's money. However, before we roll out revokable access,
      # we are just to going to log this state before taking action and cleaning up everything.
      # Note that we dont care if the user is on a trial, or in any other type of "valid" state; if they
      # have these retrictions, they can't have Copilot.
      if has_trade_restrictions
        GitHub.logger.info("Enterprise has trade restrictions")
        if has_revokable_access
          reason = COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
          Copilot::EnterpriseCleaner.call(enterprise.id, reason)
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
          return false
        end
        # We don't treat this as a special case currently, so continue to not.
      end

      # if they are in the copilot_for_business_free flag, we don't emit for them at all
      if copilot_business.copilot_for_business_free?
        GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]}"])
        return false
      end

      if copilot_business.spammy?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason)

        GitHub.dogstats.increment(
          "copilot.seat_emission.cannot_emit",
          tags: ["type:enterprise", "reason:#{reason}"]
        ) unless has_revokable_access

        GitHub.logger.info(
          "Enterprise is spammy",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )

        return false unless has_revokable_access
      elsif copilot_business.suspended?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason)

        GitHub.logger.info(
          "Enterprise is suspended",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )

        is_billed_via_zuora = enterprise.customer&.billing_platform_billing_target == BillingPlatform::Api::V1::BillingTarget::Zuora

        # If revocable access is not enabled, they can't emit when suspended.
        # Even when revocable access is enabled, they still cant emit when suspended if they are billed via Zuora
        # Otherwise, they can still be billed.
        if (has_revokable_access && is_billed_via_zuora) || !has_revokable_access
          GitHub.dogstats.increment(
            "copilot.seat_emission.cannot_emit",
            tags: ["type:enterprise", "reason:#{reason}"]
          ) unless has_revokable_access && !is_billed_via_zuora

          return false
        end
      elsif !billable_result[:billable]
        is_trial_business = copilot_business.business_object.trial? || copilot_business.business_object.dfd_trial?

        reason = if is_trial_business
          COPILOT_SEAT_EMISSION_ERRORS[:on_free_trial]
        else
          COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        end

        # The current behavior is to do nothing but log when the enterprise is not billable.
        # With revokable access, any reason for non-billability, except the enterprise having a trial, should trigger
        # revocation of seat assignment access.
        if !is_trial_business && has_revokable_access
          Copilot::EnterpriseCleaner.call(enterprise.id, reason)
        end

        GitHub.logger.info(
          "Enterprise is not billable",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )
        Copilot::Helpers.chatterbox_say("Copilot::SeatEmission for enterprise #{enterprise.id} is not billable!")

        if is_trial_business
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:enterprise", "reason:#{reason}"])
          return false
        end
        # Any other non-billable reason can emit, as they can theoretically correct their billing (and should still be billed)
        # for seats in the meantime.
      elsif copilot_business.copilot_disabled?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        Copilot::EnterpriseCleaner.call(enterprise.id, reason)

        GitHub.logger.info(
          "Copilot is disabled for this enterprise",
          "gh.copilot.enterprise.id" => enterprise.id,
          "gh.copilot.reason" => reason,
          "gh.copilot.is_standalone" => copilot_business.copilot_standalone?,
        )

        if !has_revokable_access
          GitHub.dogstats.increment(
            "copilot.seat_emission.cannot_emit",
            tags: ["type:enterprise", "reason:#{reason}"]
          )

          return false
        end
      end

      # okay, we're at the place where we can emit for them, let's check if they have emitted today
      today = Date.current

      # Kick off a job to potentially reinstate access for the enterprise. We have to do this each
      # time we check if they can emit, becuase we don't know if this is the first emission
      # since they had their assignments revoked.
      Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_later(
        enterprise_id: enterprise.id,
        reason: :enterprise_can_emit
      )

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
      has_revokable_access = copilot_organization.feature_enabled?(:copilot_revokable_access)
      billable_result = copilot_organization.copilot_billable_result
      has_trade_restrictions = billable_result[:reason] == :has_any_trade_restrictions || billable_result[:reason] == :has_full_trade_restrictions

      # This is bad. We can't legally take this user's money. However, before we roll out revokable access,
      # we are just to going to log this state before taking action and cleaning up everything.
      # Note that we dont care if the user is on a trial, or in any other type of "valid" state; if they
      # have these retrictions, they can't have Copilot.
      if has_trade_restrictions
        GitHub.logger.info("Organization has trade restrictions")
        if has_revokable_access
          reason = COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
          Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason)
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
        # We don't treat this as a special case currently, so continue to not. The check
        # for billable will catch this later.
      end

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

        if !has_revokable_access
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      end

      if copilot_organization.spammy?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]

        # Spammy businesses making it this far is not ideal but we'll just clean them up
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup

        if !has_revokable_access
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      end

      if organization.deleted? || organization.soft_deleted?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_deleted]

        # deleted also need to be cleaned up after
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup

        if !has_revokable_access
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      end

      # This is a net new code-path that we will expose in the cleaner when the
      # copilot_revokable_access flag is enabled. So, we gate it behind that flag here as well
      # to minimize changes to production code.
      if has_revokable_access && organization.archived?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_archived]
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup

        if organization.business.nil?
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      end

      # We combine these two checks into and elsif because suspension is a subset of non-billability
      # Even with revokable access, if the organization is suspended AND billed via Zuora, we can't bill them,
      # and thus cannot emit.
      if copilot_organization.suspended?
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, reason) if allow_cleanup

        if !has_revokable_access || copilot_organization.billed_via_zuora?
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      elsif !billable_result[:billable]
        reason = COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

        if allow_cleanup
          Copilot::OrganizationCleaner.call(organization.id, copilot_organization.customer_for&.id, COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable])
          GitHub.logger.info("Cleaning organization that failed copilot_billable?", {
            "gh.copilot.organization.id" => organization.id,
            "gh.copilot.reason" => reason,
          })
        end

        # Anything other than trade restrictions or being suspended with a zuora account
        # means a non-billable state the customer could techncially rcover from, so we can proceed
        # to emissions if copilot_revokable_access is enabled.
        if !has_revokable_access
          GitHub.dogstats.increment("copilot.seat_emission.cannot_emit", tags: ["type:organization", "reason:#{reason}"])
          return false
        end
      end

      # okay, we're at the place where we can emit for them, let's check if they have emitted today
      today = Date.current

      # Kick off a job to potentially reinstate access for the organization. We have to do this each
      # time we check if they can emit, becuase we don't know if this is the first emission
      # since they had their assignments revoked.
      Copilot::SeatManagement::OrgAccessReinstatementJob.perform_later(
        org_id: organization.id,
        reason: :org_can_emit
      )

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

    sig { returns(String) }
    def billing_target
      emission.dig("meuse_payload", "billing_target").to_s || emission.dig("billing_platform_payload", "billing_target").to_s
    end
  end
end
