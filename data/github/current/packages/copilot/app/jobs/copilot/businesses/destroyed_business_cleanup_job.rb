# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    class DestroyedBusinessCleanupJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::EnterpriseCleanerHelpers

      # The business is already deleted by the time this runs, so a tenant context doesn't make sense here.
      exempt_from_tenant_context_requirement

      sig { params(business_id: Integer, transaction_id: T.nilable(String)).void }
      def perform(business_id:, transaction_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.transaction.id" => transaction_id,
          "gh.business.id" => business_id
        ) do

          GitHub.logger.info("Cleaning up business post-deletion")
          # We can't use the enterprise cleaner command here because that code depends on an existing business
          # when finding the associated records.

          # We don't know if a business is standalone or not, so we need to clean all types of seat assignments
          enterprise_team_seat_assignments = Copilot::SeatAssignment
            .includes(:seats, assignable: { enterprise_team_group_mappings: :external_group })
            .where(owner_id: business_id)
            .where(assignable_type: "EnterpriseTeam")
            .to_a
            .compact
          enterprise_team_assignment = EnterpriseTeamAssignment
            .includes(:enterprise_team)
            .where(
              enterprise_team: enterprise_team_seat_assignments.map(&:assignable).map(&:id),
              assignment_type: :copilot
            )

          with_write do
            enterprise_team_seat_assignments.each { |assignment| destroy_seat_assignment(assignment, standalone: true) }
            enterprise_team_assignment.each do |team_assignment|
              destroy_enterprise_team_assignment(team_assignment, business_id)
            end

            destroy_copilot_configuration_for("Business", [business_id])
          end

          # Get all orgs associated with the business, if any
          biz_orgs = ::Organization
            .joins(:business_membership)
            .where("business_organization_memberships.business_id = ?", business_id)
            .inject([]) do |memo, org|
              memo << org if Copilot::Organization.new(org).has_configuration?
              memo
            end
          org_ids = biz_orgs.map(&:id)

          with_write do
            seat_assignments = org_ids.flat_map { |id| Copilot::SeatAssignment.for_organization_id(id) }
            seat_assignments.each { |assignment| destroy_seat_assignment(assignment) }

            destroy_copilot_configuration_for("Organization", org_ids)
          end

          # We can lean on the orphaned seat job to remove the seats associated with these assignments

          GitHub.logger.info("Finished cleaning business")
        end
      end
    end
  end
end
