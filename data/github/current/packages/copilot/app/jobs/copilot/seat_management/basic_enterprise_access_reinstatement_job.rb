# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class BasicEnterpriseAccessReinstatementJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      locked_by timeout: 5.minutes, key: ->(job) {
        job.arguments[0][:enterprise_id]
      }
      gate_with_feature_flag :copilot_basic_enterprise_access_reinstatement_job

      resolve_tenant_context do |args|
        ::Business.find_by(id: args[:enterprise_id])
      end

      sig { params(enterprise_id: Integer, reason: Symbol, transaction_id: T.nilable(Integer), payload: T.nilable(T::Hash[Symbol, String]), actor_id: T.nilable(Integer)).void }
      def perform(enterprise_id:, reason:, transaction_id: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "gh.business.id" => enterprise_id,
          "gh.copilot.reason" => reason,
          "transaction_id" => transaction_id,
          "actor_id" => actor_id
        ) do

          # First check the enterprise exists
          @enterprise = T.let(::Business.find_by(id: enterprise_id), T.nilable(::Business))
          return handle_copilot_error(
            Copilot::Errors::MissingBusinessError.new("Enterprise cannot be found.")
          ) unless @enterprise

          # If revokable access isn't enabled, there is nothing to reinstate.
          if !@enterprise.feature_enabled?(:copilot_revokable_access)
            GitHub.logger.info("Copilot revokable access feature is not enabled for this enterprise, exiting")
            return
          end

          copilot_business = Copilot::Business.new(@enterprise)

          # Non-standalone enterprises need to have seats reinstated back with their child orgs.
          if !copilot_business.is_standalone_business?
            GitHub.logger.info("Enterprise is not standalone, exiting")
            return
          end

          seat_assignments = Copilot::SeatAssignment.for_standalone_business(@enterprise)

          # There are no seat assignments, so again, there is nothing to reinstate.
          if seat_assignments.empty?
            GitHub.logger.info("No seat assignments, exiting")
            return
          end

          # No seat assignments had their access revoked.
          if !seat_assignments.any?(&:access_revoked?)
            GitHub.logger.info("No seat assignments with revoked access to restore, exiting")
            return
          end

          # At this point, we know Copilot is enabled for the enterprise and they have at least
          # one seat assignment with revoked access — we can reinstate the assignment's access.
          GitHub.logger.info("Restoring access to seat assignments")
          reinstated_count = with_write do
            seat_assignments.inject(0) do |count, seat_assignment|
              next count unless seat_assignment.access_revoked?

              GitHub.logger.info("Restoring access to seat assignment")
              seat_assignment.reinstate_access!(
                reason,
                options: { allow_non_user: true, uncancel: copilot_business.copilot_enabled? }
              )
              count + 1
            end
          end

          if reinstated_count > 0
            GitHub.logger.info(
              "Reinstated access to seat assignments",
              "gh.copilot.seat_assignment.reinstated_count" => reinstated_count
            )
          end
          GitHub.dogstats.increment("copilot.seat_management.standalone_enterprise_seat_assignment_reinstatement_job.success")
        end
      end
    end
  end
end
