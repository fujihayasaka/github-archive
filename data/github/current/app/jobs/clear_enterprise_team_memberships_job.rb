# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class ClearEnterpriseTeamMembershipsJob < DestroyDependentRecordsJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  sig { returns(Arel::Nodes::BoundSqlLiteral) }
  def custom_sql_conditions_for_next_batch

    # Though this filter should ensure race conditions are avoided when unlinking an IDP and adding new users again,
    # It works only because we don't currently have plans to update the entries after creation (as opposed to deleting and adding again).
    # For future reference, consider the following scenario if we handle updating entries in the future:
    # add user to team, link IDP, unlink IDP, update that same user while the background job is running exactly
    # between the next batch select step but right before the record is destroyed (those 2 steps are not atomic).
    # The user would be removed by mistake as the updated_at would be updated between select batch and delete.
    sql_bindings = {
      initial_start: @initial_start
    }
    Arel.sql <<-SQL, **sql_bindings
      AND updated_at <= :initial_start
    SQL
  end

  sig { params(model_name: String, model_id: Integer, association_name: Symbol, initial_start: T.nilable(Time), offset_item_id: Integer, progress: Integer, options: T::Hash[Symbol, T.untyped]).void }
  def perform(model_name, model_id, association_name, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    if offset_item_id == 0
      GitHub.logger.info(
        "info.message" => "Starting clear_enterprise_team_group_mappings_job first batch",
        "gh.enterprise_team.id" => model_id
      )

      # We want the original enqueue time of the first job to be passed around all jobs.
      # Initial start is computed only when consuming the job from the queue, so we cannot use that one for the first job.
      @initial_start = initially_enqueued_at
    else
      @initial_start = initial_start
    end

    # If we adjusted the initial_start, we need to call super with the new value instead of default super.
    super(model_name, model_id, association_name, initial_start: @initial_start, offset_item_id: offset_item_id, progress: progress, **options)
  end

  sig { params(enterprise_team: EnterpriseTeam).void }
  def self.enqueue(enterprise_team)
    job = ClearEnterpriseTeamMembershipsJob.perform_later(T.must(EnterpriseTeam.name), enterprise_team.id, :enterprise_team_memberships)
    GitHub.logger.info(
      "info.message" => "Enqueued clear_enterprise_team_memberships_job",
      "gh.enterprise_team.id" => enterprise_team.id,
      "gh.job.active_job_id" => job.job_id
    ) if job
  end

  private

  sig { returns(T.nilable(Time)) }
  attr_accessor :initial_start
end
