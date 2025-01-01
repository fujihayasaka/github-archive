# typed: strict
# frozen_string_literal: true

class ClearEnterpriseTeamOrganizationMappingsJob < ApplicationJob
  extend T::Sig

  queue_as :clear_enterprise_team_organization_mappings

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  BATCH_SIZE = 100

  sig { params(enterprise_team_id: Integer, organization_ids: T::Array[Integer]).void }
  def perform(enterprise_team_id, organization_ids)
    GitHub.logger.info(
      "info.message" => "Starting clear_enterprise_team_organization_mappings_job",
      "gh.enterprise_team.id" => enterprise_team_id,
      "gh.organization.ids" => organization_ids,
    )

    EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: enterprise_team_id) do
      GitHub.logger.info(
        "info.message" => "Acquired EnterpriseTeamOrganizationMapping job restraint lock",
        "gh.enterprise_team.id" => enterprise_team_id,
        "gh.organization.ids" => organization_ids,
      )

      enterprise_team = EnterpriseTeam.find_by(id: enterprise_team_id)
      unless validate_enterprise_team?(enterprise_team)
        GitHub.logger.error({
          "exception.message" => "Validation failed for enterprise_team_organization_mapping_job",
          "gh.enterprise_team.id" => enterprise_team_id
        })
        return
      end
      enterprise_team = T.must(enterprise_team)

      # We proceed regardless of sync flag on the team when destroying select organizations as it is called when orgs are destroyed
      organization_ids.each_slice(BATCH_SIZE) do |org_ids|
        GitHub.logger.info(
          "info.message" => "Destroying batch of enterprise_team_organization_mappings (passed orgids explicitly)",
          "gh.enterprise_team.id" => enterprise_team_id,
          "gh.organization.ids" => org_ids,
        )
        with_write do
          enterprise_team.enterprise_team_organization_mappings.where(organization_id: org_ids).destroy_all
        end
      end
    end
  end

  sig { params(enterprise_team_id: Integer, organization_ids: T::Array[Integer]).void }
  def self.enqueue(enterprise_team_id, organization_ids:)
    job = ClearEnterpriseTeamOrganizationMappingsJob.perform_later(enterprise_team_id, organization_ids)
    GitHub.logger.info(
      "info.message" => "Enqueued clear_enterprise_team_organization_mappings_job",
      "gh.enterprise_team.id" => enterprise_team_id,
      "gh.organization.ids" => organization_ids,
      "gh.job.active_job_id" => job.job_id
    ) if job
  end

  private

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).returns(T::Boolean) }
  def validate_enterprise_team?(enterprise_team)
    return false unless enterprise_team
    EnterpriseTeam.enabled_for_organizations?(business: enterprise_team.business)
  end
end
