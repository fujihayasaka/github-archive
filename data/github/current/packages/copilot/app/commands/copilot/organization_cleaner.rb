# typed: strict
# frozen_string_literal: true

module Copilot
  class OrganizationCleaner < Command
    include GitHub::Memoizer
    include Copilot::SeatManagement::SeatAssignmentHelpers

    sig { params(organization_id: Integer, customer_id: T.nilable(Integer), reason: T.nilable(String)).void }
    def initialize(organization_id, customer_id, reason = nil)
      @organization_id = organization_id
      @customer_id = customer_id
      @organization = T.let(::Organization.find_by(id: @organization_id), T.nilable(::Organization))
      @reason = T.let(reason.nil? ? "copilot_policy_changed" : reason, String)
    end

    # This job runs for an organization that has been:
    #   * deleted / soft-deleted
    #   * archived
    #   * disabled
    #   * spammy
    #   * suspended
    #   * had Copilot disabled at the enterprise level (enterprise-owned orgs only)
    #   * has any trade restrictions / other non-billable states
    # If the billable owner of the organization has copilot_revokable_access enabled, we revoke access
    # to seats. Otherwise, we clean up the organization.
    # See the Copilot::OrganizationCleanupDecider for more details.
    #
    sig { override.void }
    def perform
      GitHub.logger.with_named_tags(organization_details) do
        revocation_action = if @organization.present? && @organization.feature_enabled?(:copilot_revokable_access)
          Copilot::OrganizationCleanupDecider.new(@organization, true).get_action
        else
          :none
        end

        unless organization_can_be_cleaned?
          GitHub.logger.info("Organization cannot be cleaned")
          Copilot::ErrorReporter.report!(
            Copilot::Errors::OrganizationCannotBeCleanedError.new("Organization cannot be cleaned"),
            extra_details: organization_details,
          )
          return
        end

        with_write do
          if @organization&.feature_enabled?(:copilot_revokable_access)
            GitHub.logger.info("Revoking copilot seat access for organization")
            revoke_copilot_seat_access(revocation_action: revocation_action)
          else
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
        end
        Copilot::Instrumenter.instrument_copilot_access_revoked(@organization, @reason) unless @organization.nil?
      end
    end

    sig { params(revocation_action: Symbol).void }
    def revoke_copilot_seat_access(revocation_action:)
      if revocation_action == :none
        GitHub.logger.info("No revocation action to take")
        return
      end

      seats = Copilot::Seat.includes(:seat_assignment).where(organization_id: @organization_id)
      # Create a set of seat assignments to remove. We'll remove them all at once at the end.
      # Using a set so that we don't introduce duplicates. We could call uniq or use a hash or
      # whatever, but I like the set, ok?
      assignments_to_remove = T.let(Set.new, T::Set[Integer])

      seats.each do |seat|
        seat_assignment = seat.seat_assignment

        # We don't need to handle anything here, the DeleteOrphanedSeatJob will take care of it.
        # Technically we could create an assignment and revoke it, but this case should be extremely rare.
        if seat_assignment.nil?
          GitHub.logger.info("Seat assignment is nil, skipping seat")
          next
        end

        # When revoking access to org-level seat assignments, we only need to revoke.
        # We don't need to disassociate at this point because we want to put ourselves into a situation
        # to reinstate access without friction if the organization corrects whatever issue led to the cleaner being run.
        if revocation_action == :revoke_to_org
          # This is a noop if the assignment is already revoked, so I think we can simply call this method without
          # additional checks.
          seat_assignment.unassign_and_revoke_access!(nil, :organization_cleaned, force: true)
          next
        end

        if revocation_action == :revoke_to_enterprise
          # If we get here, that mean the revocation_action is :revoke_to_enterprise.
          # Seats associated with a non-User-level seat assignment must be disassociated into user-level assignments;
          if seat_assignment.symbolized_assignable_type != :USER
            # We'll destroy the original assignment later, so we need to keep track of it.
            assignments_to_remove.add(seat_assignment.id)
            assignment_to_revoke = create_disassociated_seat_assignment(seat.assigned_user_id, seat, seat_assignment, :organization_cleaned, nil, owner: T.must(@organization&.business))
            assignment_to_revoke.unassign_and_revoke_access!(nil, :organization_cleaned, force: true)
          else
            seat_assignment.update_columns(
              owner_type: "Business",
              owner_id: @organization&.business&.id,
            )
            seat_assignment.unassign_and_revoke_access!(nil, :organization_cleaned)
          end
        end
      end

      # All seats have been repointed to new user-level seat assignments, so we can remove the old ones
      assignments_to_remove.each_slice(500) do |slice|
        GitHub.logger.info("Destroying seat assignments", "gh.copilot.seat_assignment.ids" => slice)
        Copilot::SeatAssignment.where(id: slice).delete_all
      end
    end

    sig { returns(T::Boolean) }
    def organization_can_be_cleaned?
      if @organization.present?
        # the organization exists, so the only reason we would be calling the cleaners in is because this organization
        # has been archived, marked as spammy, suspended, isn't billable, or disabled copilot
        copilot_organization = Copilot::Organization.new(@organization)
        GitHub.logger.info("Organization exists", organization_details)

        return true if @organization.spammy? || @organization.archived? || @organization.suspended? || @organization.disabled? || @organization.deleted? || @organization.soft_deleted?
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
          "gh.org.suspended" => @organization.suspended?,
          "gh.org.deleted" => @organization.deleted?,
          "gh.org.disabled" => @organization.disabled?,
          "gh.org.soft_deleted" => @organization.soft_deleted?,
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
