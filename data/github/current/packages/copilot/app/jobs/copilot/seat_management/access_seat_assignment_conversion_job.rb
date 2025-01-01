# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class AccessSeatAssignmentConversionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag %i(copilot_seat_assignment_job copilot_access_seat_assignment_conversion_job)

      resolve_tenant_context do |args|
        ::User.find_by(id: args[:user_id])&.enterprise_managed_business
      end

      sig { params(user_id: Integer, headers: T::Hash[Symbol, String]).void }
      def perform(user_id:, headers: {})
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.headers" => headers,
          "gh.user.id" => user_id,
        ) do
          # This user came to us from an API call where they are getting access to Copilot from a SeatAssignment.
          # we need to find all of their seat assignments and convert them to seats.
          @user_id             = T.let(user_id, T.nilable(Integer))
          @headers             = T.let(headers, T.nilable(T::Hash[Symbol, String]))

          @user = T.let(::User.find_by(id: T.must(@user_id)), T.nilable(::User))
          return report_error("Invalid User") unless @user

          # This in theory should not be able to happen?
          if @user.suspended?
            return report_error("Attempting to convert seat assignments for suspended user via AccessSeatAssignmentConversionJob")
          end

          seat_assignments.each do |seat_assignment|
            assignable_type = seat_assignment.assignable_type.underscore
            GitHub.logger.info(
              "Queueing immediate seat assignment conversion via AccessSeatAssignmentConversionJob",
              "gh.copilot.seat_assignment.id" => seat_assignment.id,
              "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
              "gh.copilot.seat_assignment.assignable_type" => assignable_type,
              "gh.copilot.seat_assignment.owner.id" => seat_assignment.owner_id,
              "gh.copilot.seat_assignment.owner.type" => seat_assignment.owner_type,
            )
            Copilot::SeatManagement::SeatAssignmentConverterJob.perform_later(seat_assignment_id: seat_assignment.id)

            GitHub.dogstats.increment("copilot.seat_management.access_seat_assignment_conversion_job.seat_assignment_converted",
                                      tags: ["type:#{assignable_type}"])
          end
        end
      end

      private

      sig { returns(T::Array[Copilot::SeatAssignment]) }
      def seat_assignments
        seat_assignments = []
        user_object = T.must(@user)

        with_read do
          Copilot::SeatAssignment.where(
            assignable_id: user_object.team_ids,
            assignable_type: "Team"
          ).inject(seat_assignments) do |memo, seat_assignment|
            memo << seat_assignment if seat_assignment.requires_conversion?
            memo
          end

          Copilot::SeatAssignment.where(
            assignable_id: user_object.organization_ids,
            assignable_type: "Organization"
          ).inject(seat_assignments) do |memo, seat_assignment|
            memo << seat_assignment if seat_assignment.requires_conversion?
            memo
          end

          # this REALLY shouldn't happen because the seat is created almost immediately
          Copilot::SeatAssignment.where(
            assignable_id: user_object.id,
            assignable_type: "User"
          ).inject(seat_assignments) do |memo, seat_assignment|
            memo << seat_assignment if seat_assignment.requires_conversion?
            memo
          end

          if user_object.is_enterprise_managed?
            groups = EnterpriseTeamGroupMapping.where(
              external_group_id: ExternalIdentityGroupMembership.where(external_identity: user_object.external_identities).pluck(:external_group_id)
            ).pluck(:enterprise_team_id)

            Copilot::SeatAssignment.where(
              assignable_id: groups,
              assignable_type: "EnterpriseTeam",
              pending_cancellation_date: nil,
            ).inject(seat_assignments) do |memo, seat_assignment|
              memo << seat_assignment if seat_assignment.requires_conversion?
              memo
            end
          end
        end

        GitHub.logger.info("Found seat assignments to be converted", "gh.copilot.seat_assignments.count" => seat_assignments.count) unless seat_assignments.empty?

        seat_assignments
      end

      sig { params(message: String).void }
      def report_error(message)
        safe_headers = @headers.present? ? @headers : {}
        details = {
          "gh.user.id" => @user_id,
        }.merge(safe_headers.each_with_object({}) { |(k, v), h| h["http.request.header.#{k}"] = v })

        error = Copilot::Errors::SeatAssignmentConversionError.new(message)
        handle_copilot_error(error, details)
      end
    end
  end
end
