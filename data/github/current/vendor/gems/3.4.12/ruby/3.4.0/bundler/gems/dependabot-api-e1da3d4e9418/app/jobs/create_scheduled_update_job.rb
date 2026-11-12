# frozen_string_literal: true

# This job executes the provided update config id, running an update job
# and rebasing any open PRs
class CreateScheduledUpdateJob < ApplicationJob
  include BrokenRepoHandler

  queue_as :scheduled_updates

  def perform(update_config_id:, enqueue_scheduled_update_id: nil)
    update_config = UpdateConfig.preload(:repo, :account).active.find_by(id: update_config_id)

    return unless config_should_be_scheduled?(update_config)

    if should_handle_broken_config?(update_config) && handle_broken_config(update_config, enqueue_scheduled_update_id)
      return
    end

    start_update_run(update_config, enqueue_scheduled_update_id)
    refresh_open_grouped_prs(update_config)
  end

  private

  def config_should_be_scheduled?(update_config)
    return false unless update_config&.account&.active?
    return false if repository_is_paused_or_pausable?(update_config)

    # We check for `version_updates_enabled?` after pausing so that we include
    # pausing security updates with a PR limit of 0 for pausing, but won't
    # schedule any jobs for these.
    update_config.version_updates_enabled?
  end

  def repository_is_paused_or_pausable?(update_config)
    if update_config.repo.paused?
      update_config.event_stream.record_event(Activity::UpdateConfigEvents::CREATE_SCHEDULED_JOB_SKIPPED)
      emit_config_paused_metric(update_config)
      true
    elsif update_config.repo.should_be_paused?
      update_config.repo.pause!(event_source: "create-scheduled-job")
      true
    else
      false
    end
  end

  def emit_config_paused_metric(update_config)
    return unless update_config.dependency_groups.any?

    group_count = update_config.dependency_groups.count
    group_names = update_config.dependency_groups.limit(10).pluck(:name).join(",")

    MetricsClient.increment("grouped_update.config_paused", tags: {
                              grouped_update: true,
                              group_count: group_count,
                              group_names: group_names,
                            })
  end

  def start_update_run(update_config, enqueue_scheduled_update_id) # rubocop:disable Metrics/MethodLength
    job = UpdateJob.create!(
      command: :version,
      update_config_id: update_config.id,
      trigger_type: "schedule",
      enqueue_scheduled_update_id: enqueue_scheduled_update_id
    )

    # Log group update job creation with detailed context
    log_group_update_job_creation(job, update_config)
    if limit_exceeded(update_config)
      job.update_job_errors.create!(error_type: "open_pull_request_limit_exceeded",
                                    error_details: "Open PR limit reached or exceeded")
      job.transition_to(:cancelled)

      # Temporary, remove in a couple weeks so we don't prematurely pause repos.
      # Set the pause deadline for repos that have reached the limit
      unless update_config.repo.recently_inactive?
        update_config.repo.update(will_pause_at: rand(14..45).days.from_now.utc)
      end

      rebase_open_prs(update_config, rebase_all: true)
    else
      PrioritizedJobs::StartUpdateJob.perform_later(job)
      rebase_open_prs(update_config)
    end

    job.increment_metric("scheduled_update.triggered",
                         tags: {
                           update_schedule: update_config.update_schedule,
                           enqueue_scheduled_update_id: enqueue_scheduled_update_id,
                         })
  end

  # If the user has disabled automatic rebasing, we should check for conflicts
  # during the scheduled run.
  def rebase_open_prs(update_config, rebase_all: false)
    return if update_config.automatically_rebase_prs? && !rebase_all

    update_config.pull_requests.where(grouped_update: false).open.each do |pr|
      CheckPullRequestForConflictsJob.perform_later(
        pull_request: pr,
        ignore_rebases_disabled_setting: true,
        event_source: "job.create_scheduled_update"
      )
    end
  end

  def limit_exceeded(update_config)
    update_config.pull_requests.open.count >= update_config.open_pull_requests_limit
  end

  # The scheduled grouped update job will only create PRs for groups which do
  # not have a currently existing PR.
  #
  # If there is an open PR it should be rebased instead so we can determine
  # if any of the dependencies in the group have changed and whether or not
  # the existing PR should be rebased/closed or superseded depending on the
  # content changes the Updater encounters.
  def refresh_open_grouped_prs(update_config)
    update_config.pull_requests.open.
      joins(:dependency_group).
      where(grouped_update: true, dependency_group: { deleted_at: nil }).find_each do |pr|
      CreateScheduledRefreshJob.perform_later(
        pull_request: pr,
        event_source: "job.create_scheduled_update"
      )
    end
  end

  def log_group_update_job_creation(job, _update_config)
    if job.grouping_requested?
      log_group_update_job(job)
      log_multi_ecosystem_context(job) if job.multi_ecosystem_update?
    else
      log_individual_update_job(job)
    end
  end

  def log_group_update_job(job)
    dependency_groups = job.dependency_groups.map do |group|
      {
        name: group.name,
        applies_to: group.applies_to,
        rules: group.rules,
        sort_order: group.sort_order,
      }
    end

    log_update_job_creation(
      job,
      msg: "Created group update job",
      context: "scheduled",
      additional_data: { "gh.dependabot_api.update_job.dependency_groups": dependency_groups }
    )
  end

  def log_multi_ecosystem_context(job)
    log_update_job_creation(
      job,
      msg: "Multi-ecosystem group update job created",
      additional_data: {
        "gh.dependabot_api.update_job.multi_ecosystem_siblings_count": job.multi_ecosystem_siblings.count,
      }
    )
  end

  def log_individual_update_job(job)
    log_update_job_creation(
      job,
      msg: "Created individual update job",
      context: "individual"
    )
  end

  def log_update_job_creation(job, msg:, context: nil, additional_data: {})
    log_data = {
      msg: msg,
      "code.namespace": "CreateScheduledUpdateJob",
      **job.telemetry_attributes,
    }.merge(additional_data)

    log_data[:"gh.dependabot_api.update_job.group_creation_context"] = context if context

    Dependabot::Logger.info(log_data)
  end
end
