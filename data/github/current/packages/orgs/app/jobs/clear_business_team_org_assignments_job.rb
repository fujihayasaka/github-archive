# typed: strict
# frozen_string_literal: true

class ClearBusinessTeamOrgAssignmentsJob < ApplicationJob
  queue_as :clear_business_team_org_assignments

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 100

  sig { params(org_id: Integer).void }
  def perform(org_id)
    GitHub.logger.info(
      "info.message" => "Starting ClearBusinessTeamOrgAssignmentsJob",
      "gh.organization.id" => org_id,
    )
    assignments = BusinessTeamOrgAssignment.where(organization_id: org_id)
    business = assignments.first&.business_team&.business
    assignments.in_batches(of: BATCH_SIZE) do |batch|
      return if business&.kill_switch_enabled?("ClearBusinessTeamOrgAssignmentsJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
        "gh.organization.id": org_id,
      })

      business_teams = batch.map(&:business_team).uniq

      with_write do
        BusinessTeamOrgAssignment.throttle do
          batch.destroy_all
        end
      end

      # Instrument event if the last org assignment was removed from a business team
      business_teams.each do |business_team|
        business_team&.members_or_organizations_updated(action: :remove, operation: :org)
      end
    end
    GitHub.logger.info(
      "info.message" => "Finished ClearBusinessTeamOrgAssignmentsJob",
      "gh.organization.id" => org_id,
    )
  end

  sig { params(org_id: Integer).void }
  def self.enqueue(org_id)
    job = ClearBusinessTeamOrgAssignmentsJob.perform_later(org_id)
    GitHub.logger.info(
      "info.message" => "Enqueued ClearBusinessTeamOrgAssignmentsJob",
      "gh.organization.id" => org_id,
      "gh.job.active_job_id" => job ? job.job_id : nil
    )
  end
end
