# typed: strict
# frozen_string_literal: true

module Copilot
  # This command is called from `Copilot::SeatEmission.enterprise_can_emit?` method,
  # which is only called from the `Copilot::Billing::EnterpriseTeamEmissionJob`. Therefore,
  # it seems reasonable to conclude that this cleaner command only affects non-GHEC enterprises.
  # Out of an abundance of caution, I am leaving the `clean_business` method in place with some additional
  # logging to ensure this command isn't being called from somewhere else.
  class EnterpriseCleaner < Command
    include GitHub::Memoizer
    include Copilot::EnterpriseCleanerHelpers

    sig { params(enterprise_id: Integer, reason: T.nilable(String)).void }
    def initialize(enterprise_id, reason = nil)
      @enterprise_id = enterprise_id
      @business = T.let(::Business.includes(:organizations).find_by(id: @enterprise_id), T.nilable(::Business))
      @reason = T.let(reason.nil? ? "copilot_policy_changed" : reason, String)
    end

    # If an enterprise is found to no longer be billable, remove all seats, seat assignments, and configurations
    # for the business and its organizations.
    # Ditto if the enterprise is spammy or suspended.
    # In the case of an enterprise's enrollment in the copilot_revokable_access feature flag, simply
    # revoke access to the seat assignments.
    sig { override.void }
    def perform
      GitHub.logger.with_named_tags(business_details) do
        unless @business.present?
          GitHub.logger.info("Business does not exist")
          return
        end

        clean_action = clean_business_action

        GitHub.logger.info("Business clean result", "gh.copilot.enterprise_cleaner.clean_action" => clean_action)

        if clean_action == :none
          GitHub.logger.info("Business cannot be cleaned")
          return
        end

        if copilot_business.copilot_standalone?
          clean_standalone_business(@business, clean_action)
        else
          clean_business(@business, clean_action)
        end

        # This is a bit confusing, but it indicates we are revoking access to Copilot for the entire enterprise —
        # i.e. deleting all Copilot data.
        Copilot::Instrumenter.instrument_copilot_access_revoked(@business, @reason) if clean_action == :clean
      end
    end

    sig { params(business: ::Business, clean_result: Symbol).void }
    def clean_standalone_business(business, clean_result)
      assignments = Copilot::SeatAssignment.for_standalone_business(business)
      team_assignments = EnterpriseTeamAssignment
        .includes(:enterprise_team)
        .where(
          enterprise_team: assignments.map(&:assignable).map(&:id),
          assignment_type: :copilot
        )

      with_write do
        if clean_result == :revoke_to_enterprise
          GitHub.logger.info("Revoking access for all seat assignments associated with the enterprise")
          assignments.each { |assignment| assignment.unassign_and_revoke_access!(nil, :enterprise_cleaned, {}, force: true) }
        else
          GitHub.logger.info("Destroying all seat assignments associated with the standalone business")
          assignments.each { |assignment| destroy_seat_assignment(assignment, standalone: true) }
          team_assignments.each do |team_assignment|
            destroy_enterprise_team_assignment(team_assignment, business.id)
          end

          destroy_copilot_configuration_for("Business", [business.id])
        end
      end
    end

    sig { params(business: ::Business, clean_result: Symbol).void }
    def clean_business(business, clean_result)
      GitHub.logger.info("Cleaning GHEC business")

      assignments = Copilot::SeatAssignment.for_business(business)
      seats = Copilot::Seat.for_business(business)

      with_write do
        if clean_result == :revoke_to_enterprise
          GitHub.logger.info("Revoking access to seat assignments")
          assignments.each { |assignment| assignment.unassign_and_revoke_access!(nil, :enterprise_cleaned, {}, force: true) }
        else
          seats.each do |seat|
            destroy_seat(seat)
          end

          assignments.each do |seat_assignment|
            destroy_seat_assignment(seat_assignment)
          end

          destroy_copilot_configuration_for("Business", [business.id])
          destroy_copilot_configuration_for("Organization", business.organizations.pluck(:id))
        end
      end
    end

    sig { returns(Symbol) }
    def clean_business_action
      return :none unless @business.present?

      GitHub.logger.info("Business exists", business_details)

      should_revoke_access = @business.feature_enabled?(:copilot_revokable_access)

      if !should_revoke_access
        # This is the current behavior for enterprises.
        return :clean if @business.spammy? || @business.suspended? || copilot_business.copilot_disabled?
      else
        GitHub.logger.info("Business has copilot_revokable_access feature flag enabled")

        billable_reason = billable_result[:reason]

        # Always clean if the business has trade restrictions, we cannot take their money anyway.
        return :clean if billable_reason == :has_full_trade_restrictions || billable_reason == :has_any_trade_restrictions

        # If the enterprise is suspended and billed via Zuora, we don't have a mechanism to bill them, so we clean up
        # their Copilot data
        if billable_reason == :suspended
          return billed_via_zuora?(@business) ? :clean : :revoke_to_enterprise
        end

        return :revoke_to_enterprise if !is_billable?

        # If Copilot is disabled, or the enterprise is spammy, we can still bill for them (though they are unlikely
        # to pay in the spammy case). So, we don't clean in those cases.
        return :revoke_to_enterprise if @business.spammy? || copilot_business.copilot_disabled?
      end

      :none
    end

    sig { params(business: ::Business).returns(T::Boolean) }
    def billed_via_zuora?(business)
      business.billable_owner.customer&.billing_platform_billing_target == BillingPlatform::Api::V1::BillingTarget::Zuora
    end

    sig { returns(::Billing::MeteredBillable::MeteredServicesBillableResult) }
    memoize def billable_result
      return { billable: false, reason: :unknown } unless @business.present?
      copilot_business.copilot_billable_result
    end

    sig { returns(T::Boolean) }
    memoize def is_billable?
      billable_result[:billable]
    end

    sig { returns(T::Hash[String, T.any(Integer, T::Boolean)]) }
    memoize def business_details
      details = { "gh.business.id" => @enterprise_id }

      if @business.present?
        details.merge!({
          "gh.copilot.is_billable" => is_billable?,
          "gh.copilot.billable_reason" => billable_result[:reason],
          "gh.business.spammy" => @business.spammy?,
          "gh.business.suspended" => @business.suspended?,
          "gh.business.copilot_disabled" => copilot_business.copilot_disabled?,
          "gh.business.copilot_standalone" => copilot_business.copilot_standalone?,
        })
      end

      details
    end

    sig { returns(Copilot::Business) }
    memoize def copilot_business
      Copilot::Business.new(T.must(@business))
    end
  end
end
