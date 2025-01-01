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
    assignments.in_batches(of: BATCH_SIZE) do |batch|
      with_write do
        BusinessTeamOrgAssignment.throttle do
          batch.destroy_all
        end
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
