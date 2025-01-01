# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # This job is used to force reinstatement of access for seat assignments from stafftools for an organization or enterprise,
    # if we really really messed something up
    class ForceReinstateAccessJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      STATS_KEY = "copilot.seat_management.force_reinstate_access_job"

      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_force_reinstate_access_job

      resolve_tenant_context do |args|
        if args[:seat_assignment_id]
          seat_assignment = Copilot::SeatAssignment.find_by(id: args[:seat_assignment_id])
          case seat_assignment&.owner_type
          when "Organization"
            seat_assignment&.owner&.business
          when "Business"
            seat_assignment&.owner
          else
            nil
          end
        elsif args[:organization_id]
          ::Organization.find_by(id: args[:organization_id])&.business
        elsif args[:enterprise_id]
          ::Business.find_by(id: args[:enterprise_id])
        else
          nil
        end
      end

      sig do
        params(
          seat_assignment_id: T.nilable(Integer),
          organization_id: T.nilable(Integer),
          enterprise_id: T.nilable(Integer)
        ).void
      end
      def perform(seat_assignment_id: nil, organization_id: nil, enterprise_id: nil)
        if seat_assignment_id.nil? && organization_id.nil? && enterprise_id.nil?
          GitHub.logger.error("No seat_assignment_id, organization_id or enterprise_id provided, exiting job")
          return
        end

        organization = organization_id ? ::Organization.find_by(id: organization_id) : nil
        enterprise = enterprise_id ? ::Business.find_by(id: enterprise_id) : nil

        if organization_id && organization.nil?
          raise ArgumentError, "Invalid organization_id: #{organization_id}"
        end

        if enterprise_id && enterprise.nil?
          raise ArgumentError, "Invalid enterprise_id: #{enterprise_id}"
        end

        GitHub.logger.with_named_tags(
          "gh.org.id" => organization_id,
          "gh.business.id" => enterprise_id,
          "gh.copilot.seat_assignment.id" => seat_assignment_id
        ) do
          if seat_assignment_id
            process_single_seat_assignment(seat_assignment_id)
          else
            process_bulk_seat_assignments(organization, enterprise)
          end
        end
      end

      private

      sig { params(seat_assignment_id: Integer).void }
      def process_single_seat_assignment(seat_assignment_id)
        seat_assignment = Copilot::SeatAssignment.find_by(id: seat_assignment_id)

        if seat_assignment.nil?
          raise ArgumentError, "Invalid seat_assignment_id: #{seat_assignment_id}"
        end

        if seat_assignment.access_revoked_at.nil?
          GitHub.logger.info("Seat assignment is not revoked, nothing to do",
                             "gh.copilot.seat_assignment.id" => seat_assignment_id)
          return
        end

        with_write do
          reinstate_seat_assignment(seat_assignment)
          GitHub.logger.info("Forced reinstatement of seat assignment",
                             "gh.copilot.seat_assignment.id" => seat_assignment_id)
        end
      end

      sig do
        params(
          organization: T.nilable(::Organization),
          enterprise: T.nilable(::Business)
        ).void
      end
      def process_bulk_seat_assignments(organization, enterprise)
        seat_assignments = fetch_seat_assignments(organization, enterprise)

        if seat_assignments.empty?
          GitHub.logger.info("No seat assignments to reinstate")
          return
        end

        with_write do
          reinstated_count = seat_assignments.inject(0) do |count, seat_assignment|
            count + (reinstate_seat_assignment(seat_assignment) ? 1 : 0)
          end

          if reinstated_count > 0
            GitHub.logger.info(
              "Forced reinstatement of #{reinstated_count} seat assignment#{"s" unless reinstated_count == 1}"
            )
          end
        end
      end

      sig { params(seat_assignment: Copilot::SeatAssignment).returns(T::Boolean) }
      def reinstate_seat_assignment(seat_assignment)
        validation = seat_assignment.reinstate_validation(STATS_KEY)

        return false unless validation == :valid

        with_write do
          seat_assignment.reinstate_access!(
            :reinstated_by_staff,
            options: {
              allow_non_user: true,
              uncancel: false
            }
          )
        end

        true
      end

      sig do
        params(
          organization: T.nilable(::Organization),
          enterprise: T.nilable(::Business)
        ).returns(T::Array[Copilot::SeatAssignment])
      end
      def fetch_seat_assignments(organization, enterprise)
        with_read do
          if organization
            Copilot::SeatAssignment.for_owner(organization).where.not(access_revoked_at: nil).to_a
          elsif enterprise
            if enterprise.copilot_licensing_enabled?
              Copilot::SeatAssignment.for_owner(enterprise).where.not(access_revoked_at: nil).to_a
            else
              organization_ids = enterprise.organization_ids
              # get all of the assignments across all of the orgs and assignments owned by the enterprise (were revoked to the enterprise)
              Copilot::SeatAssignment
                .where(owner_id: organization_ids)
                .or(Copilot::SeatAssignment.where(owner_id: enterprise.id))
                .where.not(access_revoked_at: nil).to_a
            end
          else
            []
          end
        end
      end
    end
  end
end
