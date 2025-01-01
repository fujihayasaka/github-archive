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
        revocation_action = if @organization.present? && T.must(copilot_organization).feature_enabled?(:copilot_revokable_access)
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
          GitHub.dogstats.increment("copilot.organization_cleaner.skip", tags: ["reason:cannot_be_cleaned"])
          return
        end

        unless @organization.present?
          GitHub.logger.info("Organization does not exist, cleaning")
          with_write { cleanup_copilot_seat_access(@organization_id, @customer_id) }
          GitHub.dogstats.increment("copilot.organization_cleaner.cleanup", tags: ["reason:non_existent_org"])
          return
        end

        # See if the organization explicitly owns any assignments or seats.
        # If it doesn't, we will clean up the organization.
        # The cleanup_copilot_seat_access method will specifically look again for all seats and assignments
        # directly owned by the organization, and only clean those up.
        #
        # When the `copilot_revoke_to_enterprise` feature flag is enabled, seats that belong to the org
        # but have been revoked to the enterprise will be retained.
        owns_any_assignments = Copilot::SeatAssignment.for_owner(@organization).exists?
        owns_any_seats = Copilot::Seat.for_owner(@organization).exists?

        with_write do
          if T.must(copilot_organization).feature_enabled?(:copilot_revokable_access)
            if !owns_any_assignments && !owns_any_seats
              cleanup_copilot_seat_access(@organization_id, @customer_id)
              GitHub.dogstats.increment("copilot.organization_cleaner.cleanup", tags: ["reason:no_copilot_seats"])
            else
              revoke_copilot_seat_access(revocation_action: revocation_action)
            end
          else
            cleanup_copilot_seat_access(@organization_id, @customer_id)
            GitHub.dogstats.increment("copilot.organization_cleaner.cleanup", tags: ["reason:#{@reason}"])
          end
        end
      end
    end

    sig { params(org_id: Integer, customer_id: T.nilable(Integer)).void }
    def cleanup_copilot_seat_access(org_id, customer_id)
      stats = {
        copilot_enabled: 0,
        seats_cancelled: 0,
        seat_assignments_destroyed: 0,
        business_trials_destroyed: 0,
        enabled_configuration_destroyed: 0,
      }

      GitHub.logger.info("Cleaning up copilot seat access for organization")
      Copilot::BusinessTrial.where(trialable_id: org_id, trialable_type: "Organization").each do |trial|
        GitHub.logger.info(
          "Destroying business trial",
          "gh.copilot.trial.id" => trial.id,
          "gh.copilot.trial.state" => trial.state,
          "gh.copilot.trial.trial_length" => trial.trial_length,
          "gh.copilot.trial.ends_at" => trial.ends_at,
        )
        trial.destroy!
        stats[:business_trials_destroyed] += 1
      end

      # Find seats specifically owned by the organization.
      # This will not find seats that have been revoked to the enterprise.
      # We aren't using the `for_owner` scope here because we to be able to find records for organizations that
      # may have been hard deleted, i.e. no longer exist in the database.
      Copilot::Seat
        .joins(:seat_assignment)
        .where(copilot_seat_assignments: { owner_id: org_id, owner_type: "Organization" })
        .each do |seat|
          GitHub.logger.info(
            "Destroying seat",
            "gh.copilot.seat.id" => seat.id,
            "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
            "gh.copilot.seat.copilot_seat_assignment_id" => seat.copilot_seat_assignment_id,
          )
          seat.customer_id = customer_id
          seat.cancel!(reason: :organization_cleaned) # Notify the user that their seat has been removed.
          stats[:seats_cancelled] += 1
        end

      # Find seat assignments specifically owned by the organization.
      # This will not include assignments that have been revoked to the enterprise.
      # We aren't using the `for_owner` scope here because we to be able to find records for organizations that
      # may have been hard deleted, i.e. no longer exist in the database.
      Copilot::SeatAssignment
        .where(owner_id: org_id, owner_type: "Organization")
        .each do |seat_assignment|
          GitHub.logger.info(
            "Destroying seat assignment",
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.seat_assignment.organization_id" => seat_assignment.organization_id,
            "gh.copilot.seat_assignment.assignable_type" => seat_assignment.assignable_type,
            "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
          )

          seat_assignment.destroy!
          stats[:seat_assignments_destroyed] += 1
        end

      # this should always delete something because calling copilot_organization below will create a configuration
      Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org_id).each do |configuration|
        GitHub.logger.info(
          "Destroying configuration",
          "gh.copilot.configuration.id" => configuration.id
        )
        copilot_enabled = configuration.enabled?
        configuration.destroy!

        if copilot_enabled
          stats[:enabled_configuration_destroyed] += 1
          Copilot::Instrumenter.instrument_copilot_access_revoked(@organization, @reason) unless @organization.nil?
        end
      end

      if stats.values.all?(&:zero?)
        GitHub.dogstats.increment("copilot.organization_cleaner.noop")
      end
    end

    sig { params(revocation_action: Symbol).void }
    def revoke_copilot_seat_access(revocation_action:)
      GitHub.dogstats.increment("copilot.organization_cleaner.revocation_action",
        tags: ["revocation_action:#{revocation_action}"]
      )

      if revocation_action == :none
        GitHub.logger.info("No revocation action to take")
        return
      end

      if revocation_action == :clean
        cleanup_copilot_seat_access(@organization_id, @customer_id)
        return
      end

      unless revocation_action == :revoke_to_org || revocation_action == :revoke_to_enterprise
        GitHub.logger.info("Invalid revocation action",
          "gh.copilot.org_cleaner.revocation_action" => revocation_action
        )
        return
      end

      seat_assignments = Copilot::SeatAssignment.for_owner(@organization)

      # Next check to see if all assignments have already been revoked to user level assignments.
      if !seat_assignments.empty? && seat_assignments.all? { |assignment| assignment.assignable_type == "User" && assignment.access_revoked? }
        GitHub.logger.info("Organization has already revoked all its assignments into user level ones")
        return
      end

      GitHub.logger.info("Revoking copilot seat access for organization")

      if revocation_action == :revoke_to_enterprise
        # The copilot_revoke_to_enterprise feature flag is OFF right now, so this block won't run.
        handle_revoke_to_enterprise
      else
        GitHub.logger.info("Revoking all assignments to disassociated User-level assignments")

        assignments_to_remove = T.let(Set.new, T::Set[Integer])
        # Get all seats assigned by the organization, and revoke them all as disassociated User-level assignments
        seats = Copilot::Seat.includes(:seat_assignment).where(organization_id: @organization_id)

        seats.each do |seat|
          original_assignment = seat.seat_assignment

          # We don't need to handle anything here, the DeleteOrphanedSeatJob will take care of it.
          # Technically we could create an assignment and revoke it, but this case should be extremely rare.
          if original_assignment.nil?
            GitHub.logger.info("Seat does not have an assignment, skipping", "gh.copilot.seat.id" => seat.id)
            next
          end

          GitHub.logger.info("Revoking seat assignment", seat_assignment_log_details(original_assignment))

          # revoke_seat_for_user implicitly calls with_write
          revoked_assignment_id = revoke_seat_for_user(original_assignment, seat, "organization_cleaner", @reason.to_sym)

          # Add the original assignment to the set of assignments to remove unless it was already a User assignment,
          # which would have been directly revoked and returned by revoke_seat_for_user.
          assignments_to_remove.add(original_assignment.id) unless revoked_assignment_id == original_assignment.id

          GitHub.logger.info("Seat assignment revoked",
            "gh.copilot.seat_assignment.id" => revoked_assignment_id,
            "gh.copilot.owner_type" => original_assignment.owner_type,
            "gh.copilot.owner_id" => original_assignment.owner_id,
            "gh.copilot.seat.id" => seat.id,
            "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id
          )
        end

        Copilot::SeatAssignment.where(id: assignments_to_remove).find_in_batches(batch_size: 500).each do |batch|
          Copilot::SeatAssignment.throttle_writes do
            Copilot::SeatAssignment.where(id: batch.map(&:id)).delete_all
          end
        end

        disable_seat_management_for_org(org_id: @organization_id)
      end
    end

    sig { params(org_id: Integer).void }
    def disable_seat_management_for_org(org_id:)
      configuration = Copilot::Configuration.find_by(configurable_type: "Organization", configurable_id: org_id)
      if configuration.present?
        GitHub.logger.info("Disabling copilot for organization",
          "gh.copilot.configuration.id" => configuration.id,
          "gh.copilot.configuration.enabled" => configuration.enabled?
        )
        with_write { configuration.update_column(:seat_management, "disabled") }
      else
        GitHub.logger.info("No copilot configuration found for organization, skipping disable")
        handle_copilot_error(
          Copilot::Errors::MissingConfigurationError.new("No copilot configuration found for organization"),
          { 'gh.org.id': org_id }
        )
      end
    end

    # Revoking an org level assignment leads to bugs with determining access for users who might be a part of the org
    # but were never assigned a seat.
    # I'm not sure how else to revoke to an enterprise properly, so I'm leaving the functionality here for the time being.
    # This will never get hit, as the feature flag gating it is currently OFF.
    sig { void }
    def handle_revoke_to_enterprise
      copilot_org = Copilot::Organization.new(T.must(@organization))
      # Bypass validations in this very specific case of creating an immediately revoked seat assignment for
      # an org that could be in a bad state (e.g. suspended)
      copilot_org.seat_management_disable!(enforce_validation: false)
      org_seat_assignment = copilot_org.organization_seat_assignment

      unless org_seat_assignment.present?
        GitHub.logger.info("Disabling seat management did not create an organization SeatAssignment")
        handle_copilot_error(Copilot::Errors::SeatAssignmentError.new("No organization SeatAssignment created"))
        return
      end

      GitHub.logger.info("Transferring ownership of SeatAssignment to enterprise",
        "gh.business.id" => @organization&.business&.id,
        "gh.copilot.seat_assignment.id" => org_seat_assignment.id
      )
      org_seat_assignment.update_columns(
        owner_type: "Business",
        owner_id: @organization&.business&.id,
      )
      org_seat_assignment.unassign_and_revoke_access!(nil, @reason.to_sym, allow_non_user: true)
    end

    sig { returns(T::Boolean) }
    def organization_can_be_cleaned?
      return true if @organization.nil?

      # the organization exists, so the only reason we would be calling the cleaner is because this organization
      # has been archived, marked as spammy, suspended, isn't billable, or disabled copilot
      copilot_organization = Copilot::Organization.new(@organization)
      GitHub.logger.info("Organization exists", organization_details)

      return true if @organization.spammy? || @organization.archived? || @organization.suspended? || @organization.disabled? || @organization.deleted? || @organization.soft_deleted?
      # if they disabled copilot but are on a trial, don't clean them
      return false if copilot_organization.on_free_trial? || copilot_organization.pending_free_trial?

      return true if !copilot_organization.has_copilot_for_business?
      return true if !copilot_organization.copilot_billable?

      false
    end

    sig { returns(T.nilable(Copilot::Organization)) }
    memoize def copilot_organization
      return nil unless @organization.present?
      Copilot::Organization.new(@organization)
    end

    sig { returns(T::Hash[String, T.any(Integer, T::Boolean)]) }
    memoize def organization_details
      details = { "gh.org.id" => @organization_id }

      if @organization.present?
        copilot_org = T.must(copilot_organization)

        details.merge!({
          "gh.org.archived" => @organization.archived?,
          "gh.org.spammy" => @organization.spammy?,
          "gh.org.suspended" => @organization.suspended?,
          "gh.org.deleted" => @organization.deleted?,
          "gh.org.disabled" => @organization.disabled?,
          "gh.org.soft_deleted" => @organization.soft_deleted?,
          "gh.copilot.has_cfb" => copilot_org.has_copilot_for_business?,
          "gh.copilot.on_free_trial" => copilot_org.on_free_trial?,
          "gh.copilot.pending_free_trial" => copilot_org.pending_free_trial?,
          "gh.copilot.is_billable" => copilot_org.copilot_billable?,
        })
      end

      details
    end
  end
end
