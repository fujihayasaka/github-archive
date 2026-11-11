# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class EnterpriseTeamOrganizationReconciliationJob < BatchedJob
  include SecurityCenter::FanoutThrottler

  USER_NOT_FOUND_METRIC = "enterprise_team_organization_reconciliation.user_not_found"
  ADD_STATUS_NOT_FOUND_METRIC = "enterprise_team_organization_reconciliation.add_status_not_found"
  ENQUEUE_INTERVAL = 30

  queue_as :enterprise_team_organization_reconciliation

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  sig do
    params(
      args: T.untyped,
      enterprise_team_id: Integer,
      offset_item_id: Integer,
      organization_id: T.nilable(Integer),
      out_of_sync_time: Time,
      kwargs: T.untyped,
    )
    .returns(T::Array[EnterpriseTeamOrganizationMapping])
  end
  def next_batch(*args, enterprise_team_id:, offset_item_id:, organization_id: nil, out_of_sync_time: Time.zone.now, **kwargs)
    enterprise_team = get_valid_enterprise_team(enterprise_team_id: enterprise_team_id)
    return [] if enterprise_team.nil?

    if organization_id.nil?
      EnterpriseTeamOrganizationMapping
        .where(enterprise_team: enterprise_team)
        .where("id > ?", offset_item_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
    else
      # Given a single organization to process, there should only be a single mapping for a given ET
      EnterpriseTeamOrganizationMapping.where(enterprise_team: enterprise_team, organization_id: organization_id).to_a
    end
  end

  sig do
    params(
      records: T::Array[EnterpriseTeamOrganizationMapping],
      args: T.untyped,
      enterprise_team_id: Integer,
      organization_id: T.nilable(Integer),
      out_of_sync_time: Time,
      kwargs: T.untyped,
    )
    .void
  end
  def process_batch(records, *args, enterprise_team_id:, organization_id: nil, out_of_sync_time: Time.zone.now, **kwargs)
    GitHub.logger.info(
      "info.message" => "Starting process_batch for enterprise_team_organization_reconciliation_job",
      "gh.enterprise_team.id" => enterprise_team_id,
      "gh.enterprise_team.organization_mapping.count" => records.size
    )
    enterprise_team = get_valid_enterprise_team(enterprise_team_id: enterprise_team_id)
    return if enterprise_team.nil?

    # TODO: https://github.com/github/Identity-Teams/issues/1454
    EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: enterprise_team_id) do
      records.each_slice(GitHub.max_orgs_per_et_org_reconciliation_runner) do |mappings_batch|
        job = EnterpriseTeamOrganizationReconciliationRunnerJob.perform_later(
          enterprise_team: enterprise_team,
          mappings: mappings_batch,
          out_of_sync_time: out_of_sync_time
        )

        GitHub.logger.info(
          "info.message" => "Enqueued enterprise_team_organization_reconciliation_runner_job from enterprise_team_organization_reconciliation_job",
          "gh.enterprise_team.id" => enterprise_team_id,
          "gh.enterprise_team.organization_mapping.count" => mappings_batch.size,
          "gh.job.active_job_id" => job ? job.job_id : nil
        )
      end

      GitHub.logger.info(
        "info.message" => "Finished enterprise_team_organization_reconciliation_job batch processing",
        "gh.enterprise_team.id" => enterprise_team_id,
      )
    end
  end

  sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
  def fanout_jobs
    [
      EnterpriseTeamOrganizationReconciliationRunnerJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RevokeOrgMembershipAbilitiesJob,
      DeliverHookEventJob,
      AddToSearchIndexJob,
      OrganizationOrchestrationJob,
    ]
  end

  sig { returns(Integer) }
  def self.enqueue_interval
    ENQUEUE_INTERVAL
  end

  # This method attempts to enqueue an EnterpriseTeamOrganizationReconciliationJob for the given enterprise team.
  # It checks if there are any other jobs targeting the given `enterprise_team_id` with the time interval `ENQUEUE_INTERVAL`.
  # If there are no other jobs, it enqueues a new job and returns true. If there is another job, it returns false.
  sig do
    params(
      enterprise_team_id: Integer,
      organization_id: T.nilable(Integer),
      out_of_sync_time: Time
    ).returns(T::Boolean)
  end
  def self.enqueue(enterprise_team_id:, organization_id: nil, out_of_sync_time: Time.zone.now)
    enqueued = EnterpriseTeamOrganizationReconciliationJob.enqueue_once_per_interval(
      kwargs: {
        enterprise_team_id: enterprise_team_id,
        organization_id: organization_id,
        out_of_sync_time: out_of_sync_time
      },
      interval: EnterpriseTeamOrganizationReconciliationJob.enqueue_interval,
      unique_id: enterprise_team_id
    )

    message = enqueued ? "Successfully enqueued enterprise_team_organization_reconciliation_job" : "Failed to enqueue enterprise_team_organization_reconciliation_job due to interval limit"
    GitHub.logger.info(
      "info.message" => message,
      "gh.enterprise_team.id" => enterprise_team_id,
      "gh.organization.id" => organization_id,
    )
    enqueued
  end

  sig { params(enterprise_team_id: Integer).returns(T.nilable(EnterpriseTeam)) }
  private def get_valid_enterprise_team(enterprise_team_id:)
    begin
      enterprise_team = EnterpriseTeam.unscoped.find_by!(id: enterprise_team_id)
    rescue ActiveRecord::RecordNotFound => unfound_ex
      GitHub.logger.error(
        "info.message" => "Valid enterprise team not found",
        "gh.enterprise_team.id" => enterprise_team_id,
        :exception => unfound_ex
      )
      return nil
    end

    unless EnterpriseTeam.enabled_for_organizations?(business: enterprise_team.business)
      GitHub.logger.error(
        "info.message" => "Could not find valid enterprise team for enterprise_team_organization_reconciliation_job",
        "gh.enterprise_team.id" => enterprise_team_id,
      )
      return nil
    end
    enterprise_team
  end
end
