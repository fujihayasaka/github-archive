# typed: strict
# frozen_string_literal: true

class CreateBusinessTeamOrgAssignmentsJob < ApplicationJob
  queue_as :create_business_team_org_assignments

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 10.minutes, key: ->(job) {
    job.arguments[0].id
  }

  sig { params(business_team: BusinessTeam, org_ids: T::Array[Integer]).void }
  def perform(business_team, org_ids: [])
    GitHub.logger.info(
      "info.message" => "Starting CreateBusinessTeamOrgAssignmentsJob",
      "gh.team.id" => business_team.id,
      "gh.organization.ids" => org_ids
    )

    unless business_team.org_assignment_all?
      GitHub.logger.info(
        "info.message" => "CreateBusinessTeamOrgAssignmentsJob cancelled because organization_selection_type is not :all",
        "gh.team.id" => business_team.id,
        "gh.organization.ids" => org_ids
      )
      return
    end

    org_ids = business_team.organization_ids if org_ids.empty?

    business_team.add_to_organizations(org_ids: org_ids, bypass_org_assignment_selection_requirement: true)
    business_team.organization_selection_type = :selected
    with_write do
      business_team.save
    end
    update_roles_targeting_all_orgs(business_team, org_ids)

    GitHub.logger.info(
      "info.message" => "Finished CreateBusinessTeamOrgAssignmentsJob",
      "gh.team.id" => business_team.id,
      "gh.organization.ids" => org_ids
    )
  end

  sig { params(business_team: BusinessTeam, org_ids: T::Array[Integer]).void }
  def self.enqueue(business_team, org_ids: [])
    job = CreateBusinessTeamOrgAssignmentsJob.perform_later(business_team, org_ids:)
    GitHub.logger.info(
      "info.message" => "Enqueued CreateBusinessTeamOrgAssignmentsJob",
      "gh.team.id" => business_team.id,
      "gh.job.active_job_id" => job ? job.job_id : nil,
      "gh.organization.ids" => org_ids
    )
  end

  private

  sig { params(business_team: BusinessTeam, target_ids: T::Array[Integer]).void }
  def update_roles_targeting_all_orgs(business_team, target_ids)
    GitHub.logger.info(
      "info.message" => "Updating user roles targeting all_orgs to some_orgs",
      "gh.team.id" => business_team.id,
      "gh.organization.ids" => target_ids
    )
    roles_targeting_all_orgs = business_team.user_roles.where(conditions_target: UserRoleCondition::Target::AllOrgs.serialize)

    with_write do
      roles_targeting_all_orgs.each do |user_role|
        begin
          user_role.update!(conditions: UserRoleCondition.new(target: UserRoleCondition::Target::SomeOrgs, target_ids: target_ids))
        rescue ActiveRecord::RecordInvalid => e
          Failbot.report(e)
          next
        end
      end
    end
  end
end
