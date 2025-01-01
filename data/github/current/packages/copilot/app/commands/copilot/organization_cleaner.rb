# typed: strict
# frozen_string_literal: true

module Copilot
  class OrganizationCleaner < Command
    include GitHub::Memoizer

    sig { params(organization_id: Integer, customer_id: T.nilable(Integer), reason: T.nilable(String)).void }
    def initialize(organization_id, customer_id, reason = nil)
      @organization_id = organization_id
      @customer_id = customer_id
      @organization = T.let(::Organization.find_by(id: @organization_id), T.nilable(::Organization))
      @reason = T.let(reason.nil? ? "copilot_policy_changed" : reason, String)
    end

    # this is for an organization that has been deleted, archived, no longer has copilot_for_business or is spammy
    # we are gonna viciously remove all the seats and seat assignments and configurations
    sig { override.void }
    def perform
      GitHub.logger.with_named_tags(organization_details) do
        if organization_can_be_cleaned?
          with_write do
            Copilot::BusinessTrial.where(trialable_id: @organization_id, trialable_type: "Organization").each do |trial|
              GitHub.logger.info(
                "Destroying business trial",
                "gh.copilot.trial.id" => trial.id,
                "gh.copilot.trial.state" => trial.state,
                "gh.copilot.trial.trial_length" => trial.trial_length,
                "gh.copilot.trial.ends_at" => trial.ends_at,
              )

              trial.destroy!
            end

            Copilot::Seat.where(organization_id: @organization_id).each do |seat|
              GitHub.logger.info(
                "Destroying seat",
                "gh.copilot.seat.id" => seat.id,
                "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
                "gh.copilot.seat.copilot_seat_assignment_id" => seat.copilot_seat_assignment_id,
              )
              seat.customer_id = @customer_id
              seat.cancel!(reason: :organization_cleaned) # Notify the user that their seat has been removed.
            end

            Copilot::SeatAssignment.where(organization_id: @organization_id).each do |seat_assignment|
              GitHub.logger.info(
                "Destroying seat assignment",
                "gh.copilot.seat_assignment.id" => seat_assignment.id,
                "gh.copilot.seat_assignment.organization_id" => seat_assignment.organization_id,
                "gh.copilot.seat_assignment.assignable_type" => seat_assignment.assignable_type,
                "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
              )

              seat_assignment.destroy!
            end

            # this should always delete something because calling copilot_organization below will create a configuration
            Copilot::Configuration.where(configurable_type: "Organization", configurable_id: @organization_id).each do |configuration|
              GitHub.logger.info(
                "Destroying configuration",
                "gh.copilot.configuration.id" => configuration.id
              )
              configuration.destroy!
            end
          end
          Copilot::Instrumenter.instrument_copilot_access_revoked(@organization, @reason) unless @organization.nil?
        else
          GitHub.logger.info("Organization cannot be cleaned")
          Copilot::ErrorReporter.report!(
            Copilot::Errors::OrganizationCannotBeCleanedError.new("Organization cannot be cleaned"),
            extra_details: organization_details,
          )
        end
      end
    end

    sig { returns(T::Boolean) }
    def organization_can_be_cleaned?
      if @organization.present?
        # the organization exists, so the only reason we would be calling the cleaners in is because this organization
        # has been archived, marked as spammy, suspended, isn't billable, or disabled copilot
        copilot_organization = Copilot::Organization.new(@organization)
        GitHub.logger.info("Organization exists", organization_details)

        return true if @organization.spammy? || @organization.archived? || @organization.suspended? || @organization.disabled?
        # if they disabled copilot but are on a trial, don't clean them
        return false if copilot_organization.on_free_trial? || copilot_organization.pending_free_trial?
        return true if !copilot_organization.has_copilot_for_business?
        return true if !copilot_organization.copilot_billable?

        false
      else
        GitHub.logger.info("Organization does not exist, continuing")
        true
      end
    end

    sig { returns(T::Hash[String, T.any(Integer, T::Boolean)]) }
    memoize def organization_details
      details = { "gh.org.id" => @organization_id }

      if @organization.present?
        copilot_organization = Copilot::Organization.new(@organization)

        details.merge!({
          "gh.org.archived" => @organization.archived?,
          "gh.org.spammy" => @organization.spammy?,
          "gh.copilot.has_cfb" => copilot_organization.has_copilot_for_business?,
          "gh.copilot.on_free_trial" => copilot_organization.on_free_trial?,
          "gh.copilot.pending_free_trial" => copilot_organization.pending_free_trial?,
          "gh.copilot.is_billable" => copilot_organization.copilot_billable?,
        })
      end

      details
    end
  end
end
