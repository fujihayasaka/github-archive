# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrganizationDeduplicateJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      gate_with_feature_flag :copilot_organization_deduplicate_job

      resolve_tenant_context do |org_id|
        ::Organization.find(org_id).business
      end

      sig do
        params(
          organization_id: Integer,
        ).void
      end
      def perform(organization_id)
        @organization_id = T.let(organization_id, T.nilable(Integer))
        organization = ::Organization.find_by(id: organization_id)
        return unless organization.present?

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
        ) do
          GitHub.logger.info("Loading duplicate seats for organization")

          sql = Arel.sql(<<-SQL, organization_id: organization_id)
            SELECT
            `assigned_user_id`
            FROM `copilot_seats`
            WHERE `organization_id` = :organization_id
            GROUP BY `copilot_seats`.`assigned_user_id`
            HAVING (count(*) > 1)
          SQL

          duplicate_assigned_user_ids = Copilot::Seat.connection.select_rows(sql)

          GitHub.logger.info(
            "Loaded duplicate seats for organization",
            "gh.copilot.duplicate_seat_count" => duplicate_assigned_user_ids.count,
          )

          GitHub.dogstats.gauge("gh.copilot.duplicate_assigned_user_count", duplicate_assigned_user_ids.count, tags: ["owner:organization"])

          with_write do
            duplicate_assigned_user_ids.each do |assigned_user_id|
              GitHub.logger.info(
                "Processing duplicate seats for user",
                "gh.user.id" => assigned_user_id,
              )
              deleted_seats = Copilot::Seat.
                              where(organization_id: organization_id, assigned_user_id: assigned_user_id).
                              offset(1).destroy_all

              GitHub.logger.info(
                "Deleted duplicate seats",
                "gh.user.id" => assigned_user_id,
                "gh.copilot.deleted_seat_count" => deleted_seats.count,
              )
            end
          end
        end
      rescue StandardError => error # rubocop:todo Lint/RescueException
        handle_copilot_error(Copilot::Errors::CopilotError.from_error(error), { "gh.organization.id" => organization_id })
      end
    end
  end
end
