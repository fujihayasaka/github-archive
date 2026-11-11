# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseSeatDeduplicateJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      queue_as :copilot_enterprise_seat_deduplicate

      locked_by timeout: 10.minutes, key: ->(job) {
        job.arguments[0]
      }

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

        GitHub.logger.with_named_tags("gh.business.id" => business_id) do
          GitHub.logger.info("Loading duplicate user seats for enterprise")

          # Find all seats for users with one or more seats.
          # They will have these seats through EnterpriseTeam / BusinessTeam seat assignments,
          # directly assigned active User assignments, or User seat assignments
          # that have had their access revoked
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

          duplicate_user_and_assignment_ids = Copilot::Seat.connection.select_rows(sql)

          GitHub.logger.info(
            "Loaded duplicate seats for enterprise",
            "gh.copilot.duplicate_seat_count" => duplicate_user_and_assignment_ids.count,
          )

          GitHub.dogstats.count("gh.copilot.duplicate_assigned_user_count", duplicate_user_and_assignment_ids.count, tags: ["copilot_owner:business"])

          duplicate_user_and_assignment_ids.each do |user_id, _|
            GitHub.logger.info(
              "Processing duplicate seats for user",
              "gh.user.id" => user_id,
            )

            # Collect all seats for the user under this business, save for one
            seats_for_user = Copilot::Seat
              .includes(:seat_assignment)
              .where(assigned_user_id: user_id, seat_assignment: { owner_id: business_id, owner_type: "Business" })
              .offset(1)

            GitHub.logger.info(
              "Found duplicate seats for user",
              "gh.user.id" => user_id,
              "gh.copilot.duplicate_seat_count" => seats_for_user.count
            )

            deleted_seat_count = Copilot::Seat.throttle_writes { seats_for_user.destroy_all }.count

            GitHub.logger.info(
              "Deleted duplicate seats",
              "gh.user.id" => user_id,
              "gh.copilot.deleted_seat_count" => deleted_seat_count,
            ) unless deleted_seat_count.zero?
          end
        end
      rescue StandardError => error
        handle_copilot_error(
          Copilot::Errors::EnterpriseSeatDeduplicationError.from_error(error), { "gh.business.id" => business_id }
        )
      end
    end
  end
end
