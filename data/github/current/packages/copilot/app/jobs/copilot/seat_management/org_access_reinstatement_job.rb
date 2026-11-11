# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrgAccessReinstatementJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      STATS_KEY = "copilot.seat_management.org_access_reinstatement_job"

      locked_by timeout: 5.minutes, key: ->(job) {
        job.arguments[0][:org_id]
      }

      gate_with_feature_flag :copilot_org_access_reinstatement_job

      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:org_id])&.business
      end

      sig do
        params(
          org_id: Integer,
          reason: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(org_id:, reason:, transaction_id: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "gh.org.id" => org_id,
          "gh.copilot.reason" => reason,
          "transaction_id" => transaction_id,
          "actor_id" => actor_id
        ) do
          @reason = T.let(reason, T.nilable(Symbol))

          org = ::Organization.find_by(id: org_id)
          # Error out if the organization doesn't exist
          if org.nil?
            GitHub.logger.info("Invalid organization", "gh.org.id" => org_id)
            handle_copilot_error(
              Copilot::Errors::OrganizationResolutionError.new("Invalid organization")
            )
            GitHub.dogstats.increment("#{STATS_KEY}.skipped", tags: ["reason:org_not_found"])
            return
          end

          copilot_org = Copilot::Organization.new(org)

          # If the org doesn't have copilot, we don't need to reinstate anything.
          # Note that this is not the same as the org have Copilot's seat management setting
          # set to `disabled`. In that case, we should reinstate access, though we won't
          # uncancel the seat assignments.
          if !copilot_org.copilot_enabled?
            GitHub.logger.error("Organization does not have Copilot enabled, skipping reinstatement")
            GitHub.dogstats.increment("#{STATS_KEY}.skipped", tags: ["reason:copilot_disabled"])
            return
          end

          # Next we need to get all seat assignments that have a non-nil access_revoked_at
          # field for the org.
          #
          # There are two cases of org we need to get seat assignments for:
          # 1. Orgs that are not owned by a parent enterprise.
          # 2. Orgs that have a parent enterprise.
          #
          # In the former case, we can just get the seat assignments for the org.
          # In the latter case, we need to get the seat assignments from the parent enterprise,
          # filtering them by the current org members who are not suspended.
          # We have to do this because when seat assignment access is revoked to the enterprise,
          # we create new user-level seat assignments for the org members.
          seat_assignments = get_seat_assignments_for_org(org)
          if seat_assignments.empty? || !seat_assignments.any?(&:access_revoked?)
            # If there are no seat assignments, or none of them have access revoked,
            # we don't need to do anything.
            GitHub.logger.info("No seat assignments to reinstate")
            GitHub.dogstats.increment("#{STATS_KEY}.skipped", tags: ["reason:no_seat_assignments_revoked"])
            return
          end

          is_copilot_enabled_for_all = copilot_org.seat_management_enabled_for_all?

          # If seat management was enabled for all, we need to get (or create a new) org-level seat assignment.
          # When we loop through the seats, we'll repoint each valid one to the org-level seat assignment.
          # Then we can reinstate the org-level seat assignment, and destroy the user-level ones.
          org_assignment = get_or_create_org_seat_assignment!(org, seat_assignments) if is_copilot_enabled_for_all
          GitHub.logger.info("Found SeatAssignments for org, proceeding")

          should_repoint_to_org_assignment = org_assignment.present? && is_copilot_enabled_for_all
          assignment_ids_to_repoint = []

          # Do we need to run the cleaner decider again to make sure nothing else
          # is wrong with the org?
          reinstated_count = seat_assignments.inject(0) do |count, seat_assignment|
            reinstate_validation = seat_assignment.reinstate_validation(STATS_KEY)
            unless reinstate_validation == :valid
              next count
            end

            # User assignments for users who are still in the org will need to be repointed
            # to the org-level assignment when seat management is enabled for all.
            # We will perform that lookup separately so we can group the update call.
            if seat_assignment.assignable_type == "User" && should_repoint_to_org_assignment
              GitHub.logger.info("Pointing user seat to org assignment",
                  "gh.user.id" => seat_assignment.assignable_id,
                  "gh.copilot.seat_assignment.id" => seat_assignment.id
                )
              assignment_ids_to_repoint << seat_assignment.id
              next count
            elsif seat_assignment.assignable_type == "Team" && should_repoint_to_org_assignment
              GitHub.logger.info("Pointing team seats to org assignment",
                  "gh.team.id" => seat_assignment.assignable_id,
                  "gh.copilot.seat_assignment.id" => seat_assignment.id
                )
              assignment_ids_to_repoint << seat_assignment.id
              next count
            end

            GitHub.logger.info("Found valid SeatAssignment",
              "gh.copilot.seat_assignment.id" => seat_assignment.id,
              "gh.copilot.seat_assignment.assignable_type" => seat_assignment.assignable_type
            )

            # We can reinstate the seat assignment
            # We have to ensure we reset the organization_id to the current org, for tracking
            # it back to its original owner.
            params = { owner_id: org.id, owner_type: "Organization", organization_id: org.id }

            if seat_assignment.owner_type == "Business"
              GitHub.dogstats.increment("#{STATS_KEY}.seat_assignment_repointed")
              GitHub.logger.info("Repointing SeatAssignment ownership from business to org")
            end

            with_write do
              seat_assignment.reinstate_access!(
                reason,
                options: {
                  allow_non_user: true,
                  uncancel: !copilot_org.seat_management_disabled?,
                  extra_params: params,
                }
              )
            end
            count + 1
          end

          if should_repoint_to_org_assignment
            GitHub.logger.info("Repointing seats for user-level seat assignments to org-level assignment",
              "gh.copilot.seat_assignment.ids" => assignment_ids_to_repoint,
            )

            seats_to_repoint = Copilot::Seat.where(copilot_seat_assignment_id: assignment_ids_to_repoint)
            other_assignments_to_destroy = Copilot::SeatAssignment.where(id: assignment_ids_to_repoint)

            with_write do
              seats_to_repoint.update_all(copilot_seat_assignment_id: org_assignment.id)

              other_assignments_to_destroy.each do |assignment|
                assignment.log_reinstatement_and_refund_user(reason)
              end

              other_assignments_to_destroy.destroy_all
            end
            reinstated_count += 1
          end

          if reinstated_count > 0
            GitHub.logger.info(
              "Reinstated access to seat assignments",
              "gh.copilot.seat_assignment.reinstated_count" => reinstated_count
            )
          end
          GitHub.dogstats.increment("copilot.seat_management.org_access_reinstatement_job.success")
        end
      end

      private

      sig { params(org: ::Organization, assignments: T::Array[Copilot::SeatAssignment]).returns(Copilot::SeatAssignment) }
      def get_or_create_org_seat_assignment!(org, assignments)
        GitHub.logger.info("Organization seat management enabled for all, finding or creating org-level seat assignment")
        # We need to get the org seat assignment for the org
        # If it doesn't exist, we need to create it.
        # Technically we should not need to find an assignment owned by the parent enterprise,
        # since seat management can only be enabled for all AFTER access is reinstated.
        org_assignment = assignments.find do |assignment|
          assignment.assignable_type == "Organization" &&
          (
            assignment.owner_type == "Organization" && assignment.owner_id == org.id ||
            assignment.owner_type == "Business" && assignment.organization_id == org.id
          )
        end

        if org_assignment.nil?
          org_assignment = with_write do
            Copilot::SeatAssignment.create!(
              owner_id: org.id,
              owner_type: "Organization",
              organization_id: org.id,
              assignable_type: "Organization",
              assignable_id: org.id,
              assigning_user: org.admins.first
            )
          end
        end

        org_assignment
      end

      # Determine if the seat assignment is owned by a parent enterprise to which the org
      # no longer belongs.
      sig { params(org: ::Organization, assignment: Copilot::SeatAssignment).returns(T::Boolean) }
      def org_seat_assignment_managed_by_former_enterprise?(org, assignment)
        assignment.owner_type == "Business" && assignment.organization_id == org.id && !org.business.present?
      end

      # In the case of an org that was owned by a parent enterprise, we need to filter out
      # the assignments were revoked to that enterprise.
      # We need to do this because we don't want to reinstate access to the org
      # for those assignments, since they are owned by the parent enterprise.
      sig { params(org: ::Organization, assignments: T::Array[Copilot::SeatAssignment]).returns(T::Array[Copilot::SeatAssignment]) }
      def filter_assignments_from_previous_enterprise(org, assignments)
        assignments.reject do |assignment|
          if org_seat_assignment_managed_by_former_enterprise?(org, assignment)
            GitHub.logger.info("SeatAssignment is owned by a former parent enterprise, skipping reinstatement",
              "gh.copilot.seat_assignment.id" => assignment.id,
              "gh.org.id" => org.id,
              "gh.business.id" => assignment.owner_id
            )
            GitHub.dogstats.increment("#{STATS_KEY}.seat_assignment_owned_by_former_enterprise")
            true
          else
            false
          end
        end
      end

      sig { params(lookup: T::Hash[String, T::Boolean], assignment: Copilot::SeatAssignment).returns(T::Boolean) }
      def deduplicate_assignment?(lookup, assignment)
        has_same_assignment = lookup.fetch("#{assignment.assignable_id}_#{assignment.assignable_type}", false)

        if has_same_assignment
          handle_copilot_error(
            Copilot::Errors::DuplicateRevokedAssignmentError.new(
              "Organization and enterprise each have a revoked assignment for the same assignable"
            )
          )
          GitHub.dogstats.increment("#{STATS_KEY}.seat_assignment_duplicate_assignable")
        end

        has_same_assignment
      end

      sig { params(org: ::Organization).returns(T::Array[Copilot::SeatAssignment]) }
      def get_seat_assignments_for_org(org)
        # We only revoke seat assignments to the enterprise level in a few situations:
        # 1. The org is archived
        # 2. The org is removed from the enterprise
        # 3. The org is deleted
        # The third case is unrecoverable, so we should only have seat assignments at the
        # enterprise level in case of archiving or removal.
        enterprise_assignments = if org.business.present?
          Copilot::SeatAssignment
            .includes(:assignable)
            .joins(:seats)
            .where(seats: { organization_id: org.id })
            .where.not(access_revoked_at: nil)
            .where(organization_id: org.id, owner_type: "Business", owner_id: T.must(org.business).id)
            .distinct
            .to_a
        else
          []
        end

        unless enterprise_assignments.empty?
          GitHub.logger.info("Found revoked SeatAssignments owned by parent enterprise")
          GitHub.dogstats.increment("#{STATS_KEY}.has_enterprise_assignments")
        end

        # Ensure we find any revoked seat assignments as well as an org-level assignment, if it exists.
        org_assignments = Copilot::SeatAssignment
          .includes(:assignable)
          .for_owner(org)
          .where("access_revoked_at IS NOT NULL OR (assignable_type = 'Organization' AND assignable_id = ?)", org.id)
          .to_a

        if enterprise_assignments.any?
          # Make a lookup table in the unlikely event the same assignable exists in both the org and the enterprise,
          # let the enterprise win.
          lookup = enterprise_assignments.inject({}) do |memo, assignment|
            key = "#{assignment.assignable_id}_#{assignment.assignable_type}"
            memo[key] = true
            memo
          end

          return enterprise_assignments.concat(
            org_assignments.reject { |assignment| deduplicate_assignment?(lookup, assignment) }
          )
        end

        filter_assignments_from_previous_enterprise(org, org_assignments)
      end
    end
  end
end
