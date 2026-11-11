# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class DuplicateSeatCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 3.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_organization_deduplicate_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        ) do
          sql = Arel.sql(<<-SQL)
            SELECT count(*), copilot_seat_assignments.owner_id
            FROM copilot_seat_assignments
            INNER JOIN copilot_seats ON copilot_seat_assignments.id = copilot_seats.copilot_seat_assignment_id
            WHERE copilot_seat_assignments.owner_type = 'Organization'
            GROUP BY copilot_seat_assignments.owner_id, copilot_seats.assigned_user_id
            HAVING (count(*) > 1)
          SQL

          Copilot::SeatAssignment.connection.select_rows(sql).each do |count, organization_id|
            GitHub.logger.info("Queueing organization deduplication", "gh.org.id" => organization_id, "gh.copilot.duplicate.count" => count)
            Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(organization_id)
          end
        end
      end
    end
  end
end
