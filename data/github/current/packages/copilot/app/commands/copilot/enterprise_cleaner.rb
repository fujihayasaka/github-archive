# typed: strict
# frozen_string_literal: true

module Copilot
  class EnterpriseCleaner < Command
    extend T::Sig
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
    sig { override.void }
    def perform
      GitHub.logger.with_named_tags(business_details) do
        unless @business.present?
          GitHub.logger.info("Business does not exist")
          return
        end

        if business_can_be_cleaned?
          with_write do
            if copilot_business.copilot_standalone?
              clean_standalone_business(@business)
            else
              clean_business(@business)
            end
          end
          Copilot::Instrumenter.instrument_copilot_access_revoked(@business, @reason)
        else
          GitHub.logger.info("Business cannot be cleaned")
          Copilot::ErrorReporter.report!(
            Copilot::Errors::BusinessCannotBeCleanedError.new("Business can be billed"),
            extra_details: business_details,
          )
        end
      end
    end

    sig { params(business: ::Business).void }
    def clean_standalone_business(business)
      GitHub.logger.info("Cleaning standalone business", business_id: business.id)

      assignments = Copilot::SeatAssignment.for_standalone_business(business)
      team_assignments = EnterpriseTeamAssignment
        .includes(:enterprise_team)
        .where(
          enterprise_team: assignments.map(&:assignable).map(&:id),
          assignment_type: :copilot
        )

      assignments.each { |assignment| destroy_seat_assignment(assignment, standalone: true) }
      team_assignments.each do |team_assignment|
        destroy_enterprise_team_assignment(team_assignment, T.must(business.id))
      end

      destroy_copilot_configuration_for("Business", [T.must(business.id)])
    end

    sig { params(business: ::Business).void }
    def clean_business(business)
      Copilot::Seat.for_business(business).each do |seat|
        destroy_seat(seat)
      end

      Copilot::SeatAssignment.for_business(business).each do |seat_assignment|
        destroy_seat_assignment(seat_assignment)
      end

      destroy_copilot_configuration_for("Business", [T.must(business.id)])
      destroy_copilot_configuration_for("Organization", business.organizations.pluck(:id))
    end

    sig { returns(T::Boolean) }
    def business_can_be_cleaned?
      return false unless @business.present?
      GitHub.logger.info("Business exists", business_details)

      return true if @business.spammy? || @business.suspended? || copilot_business.copilot_disabled?

      false
    end

    sig { returns(T::Boolean) }
    memoize def is_billable?
      return false unless @business.present?
      copilot_business.copilot_billable?
    end

    sig { returns(T::Hash[String, T.any(Integer, T::Boolean)]) }
    memoize def business_details
      details = { "gh.business.id" => @enterprise_id }

      if @business.present?
        details.merge!({
          "gh.copilot.is_billable" => is_billable?,
          "gh.business.spammy" => @business.spammy?,
          "gh.business.suspended" => @business.suspended?,
          "gh.business.copilot_disabled" => copilot_business.copilot_disabled?,
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
