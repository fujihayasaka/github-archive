# typed: strict
# frozen_string_literal: true

class BusinessTeamOrgAssignmentsInstrumentationJob < ApplicationJob
  queue_as :business_team_org_assignments_instrumentation

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 100

  sig do
    params(
      business_team: BusinessTeam,
      organization_selection_type: Symbol,
      previous_org_ids: T::Array[Integer]
    ).void
  end
  def perform(business_team, organization_selection_type, previous_org_ids)
    business = business_team.business
    organizations = business&.organizations
    return unless organizations
    return unless business.feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)

    if organization_selection_type == :disabled
      organizations.where(id: previous_org_ids).find_each(batch_size: BATCH_SIZE) do |org|
        business_team.instrument :remove_from_organization, org: org, business: business
      end
    elsif organization_selection_type == :all
      organizations.where.not(id: previous_org_ids).find_each(batch_size: BATCH_SIZE) do |org|
        business_team.instrument :add_to_organization, org: org, business: business
      end
    end
  end
end
