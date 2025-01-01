# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseSeatDeduplicateJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      gate_with_feature_flag :copilot_enterprise_seat_deduplicate_job

      resolve_tenant_context do |business_id|
        ::Business.find(business_id)
      end

      sig do
        params(
          business_id: Integer,
        ).void
      end
      def perform(business_id)
        @business_id = T.let(business_id, T.nilable(Integer))
        business = ::Business.find_by(id: business_id)
        return unless business.present?

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.business.id" => business_id,
        ) do
          GitHub.logger.info("Loading duplicate user seats for enterprise")

          # Find all seats for users with one or more seats.
          # They will have these seats through EnterpriseTeam seat assignments,
          # or User seat assignments that have had their access revoked.
          sql = Arel.sql(<<-SQL, business_id: business_id)
            SELECT
            cs.assigned_user_id, csa.id
            FROM copilot_seats cs
            LEFT JOIN copilot_seat_assignments csa
            ON cs.copilot_seat_assignment_id = csa.id
            WHERE csa.owner_id = :business_id
            AND csa.owner_type = 'Business'
            GROUP BY cs.assigned_user_id
            HAVING (count(*) > 1)
          SQL

          duplicate_assigned_user_ids = Copilot::Seat.connection.select_rows(sql)

          GitHub.logger.info(
            "Loaded duplicate seats for enterprise",
            "gh.copilot.duplicate_seat_count" => duplicate_assigned_user_ids.count,
          )

          GitHub.dogstats.gauge("gh.copilot.duplicate_assigned_user_count", duplicate_assigned_user_ids.count, tags: ["owner:business"])

          with_write do
            duplicate_assigned_user_ids.each do |assigned_user_id|
              GitHub.logger.info(
                "Processing duplicate seats for user",
                "gh.user.id" => assigned_user_id,
              )
              deleted_seats = Copilot::Seat
                .includes(:seat_assignment)
                .where(assigned_user_id: assigned_user_id, seat_assignment: { owner_id: business_id, owner_type: "Business" })
                .offset(1)
                .destroy_all

              GitHub.logger.info(
                "Deleted duplicate seats",
                "gh.user.id" => assigned_user_id,
                "gh.copilot.deleted_seat_count" => deleted_seats.count,
              )
            end
          end
        end
      rescue StandardError => error # rubocop:todo Lint/RescueException
        handle_copilot_error(Copilot::Errors::CopilotError.from_error(error), { "gh.business.id" => business_id })
      end
    end
  end
end
