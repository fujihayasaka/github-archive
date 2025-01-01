# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrgAccessReinstatementJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

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

          # Error out if the organization doesn't exist
          org = ::Organization.find_by(id: org_id)
          return handle_copilot_error(
            Copilot::Errors::OrganizationResolutionError.new("Invalid organization")
          ) unless org

          copilot_org = Copilot::Organization.new(org)

          if !copilot_org.feature_enabled?(:copilot_revokable_access)
            GitHub.logger.info("Organization does not have revokable access enabled, skipping reinstatement")
            return
          end

          # If the org doesn't have copilot, we don't need to reinstate anything.
          # Note that this is not the same as the org have Copilot's seat management setting
          # set to `disabled`. That case means we should reinstate access, though we won't
          # uncancel the seat assignments.
          if !copilot_org.copilot_enabled?
            GitHub.logger.error("Organization does not have Copilot enabled, skipping reinstatement")
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
          if seat_assignments.empty?
            GitHub.logger.info("No seat assignments to reinstate")
            return
          end

          org_member_ids = org.member_ids

          # do we need to run the cleaner decider again to make sure nothing else
          # is wrong with the org?
          with_write do
            reinstated_count = seat_assignments.inject(0) do |count, seat_assignment|
              assignable = seat_assignment.assignable
              # Suspended users will stay suspended
              if assignable.is_a?(::User)
                if assignable.suspended?
                  GitHub.logger.info("Seat assignment #{seat_assignment.id} is suspended, skipping reinstatement")
                  next count
                end

                next count unless org_member_ids.include?(assignable.id)
              end

              # we can reinstate the seat assignment
              params = { owner_id: org.id, owner_type: "Organization" }

              seat_assignment.reinstate_access!(
                reason,
                options: {
                  allow_non_user: true,
                  uncancel: !copilot_org.seat_management_disabled?,
                  extra_params: params,
                }
              )

              count + 1
            end

            if reinstated_count > 0
              GitHub.logger.info(
                "Reinstated access to seat assignments",
                "gh.copilot.seat_assignment.reinstated_count" => reinstated_count
              )
            end
            GitHub.dogstats.increment("copilot.seat_management.organization_seat_assignment_reinstatement_job.success")
          end
        end
      end

      private

      sig { params(org: ::Organization).returns(T::Array[Copilot::SeatAssignment]) }
      def get_seat_assignments_for_org(org)
        # We only revoke seat assignments to the enterprise level in two situations:
        # 1. If the org is archived
        # 2. If the org is deleted
        # Only the first case is recoverable.
        if org.business.present? && @reason == :organization_unarchived
          Copilot::Seat
            .includes(:seat_assignment)
            .where(organization_id: org.id)
            .where.not(seat_assignment: { access_revoked_at: nil })
            .map(&:seat_assignment)
            .compact
        else
          Copilot::SeatAssignment.for_owner(org).where.not(access_revoked_at: nil).to_a
        end
      end
    end
  end
end
