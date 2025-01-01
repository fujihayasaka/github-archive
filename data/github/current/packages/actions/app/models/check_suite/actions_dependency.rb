# typed: false
# frozen_string_literal: true

# Actions-specific functionality for check suites (AKA workflow runs)

# require 'securerandom' for unique external_id generation
require "securerandom"

module CheckSuite::ActionsDependency
  extend ActiveSupport::Concern

  include CheckSuite::NewsiesAdapter
  class ExpiredWorkflowRunError < CheckSuite::NotRerequestableError; end
  class PreviousJobAttemptError < CheckSuite::NotRerequestableError; end

  # Events that can trigger workflows, see also
  # https://github.com/github/launch/blob/07429378c3d40c18bef6e9216547191f26879905/flow/flowevents/eventtypes.go#L80-L110

  # Webhook events the Actions app reacts to
  ACTIONS_WEBHOOK_EVENTS = %w[
    branch_protection_rule
    check_run
    check_suite
    create
    delete
    discussion
    discussion_comment
    deployment_status
    deployment
    fork
    gollum
    issue_comment
    issues
    label
    merge_group
    milestone
    page_build
    project_card
    project_column
    project
    public
    pull_request_review_comment
    pull_request_review
    pull_request
    push
    registry_package
    release
    repository_dispatch
    status
    watch
    workflow_dispatch
    workflow_run
  ].freeze

  # Overall list of events that can occur in relation to Actions, these are webhook events
  # plus some "virtual" events like `schedule`
  ACTIONS_EVENTS = ACTIONS_WEBHOOK_EVENTS | %w[
    schedule
    pull_request_target
  ].freeze

  VISIBLE_ACTIONS_EVENTS = %w[push pull_request pull_request_review pull_request_target deployment deployment_status merge_group].freeze

  included do
    scope :for_workflow, ->(name) { where(name: name) }
  end

  def actions_app?
    return @actions_app if defined?(@actions_app)
    @actions_app = github_app_id.present? && (Integration.launch_github_app?(github_app_id) || Integration.launch_lab_github_app?(github_app_id))
  end

  def healable_for_actions?
    actions_app? && explicit_completion && (conclusion.nil? || inconsistent_status?) && latest_check_runs.all?(&:concluded?)
  end

  # Due to https://github.com/github/c2c-actions-checks/issues/1439 it is possible that check suites can get in an inconsistent state
  def inconsistent_status?
    conclusion.present? && status.present? && status != "completed"
  end

  def mark_as_complete!
    return unless healable_for_actions?
    explicit_conclusion = latest_check_runs.any? ? calculate_rollup_conclusion(latest_check_runs) : "cancelled"
    set_complete_explicitly! explicit_conclusion
  end

  def workflow_name
    name.present? ? name : Actions::Workflow::PLACEHOLDER_NAME
  end

  def notify_workflow_run(workflow_run_id:, creator:, action:)
    # These events are enqueued only if the creator is GitHub Actions.

    if actions_app? && !startup_failure?
      payload = {
        run_id: workflow_run_id,
        action: action,
        actor_id: creator.id,
        repository_id: self.repository_id,
        primary_resource: workflow_run.attributes
      }
      ActiveRecord::Base.connected_to(role: :reading) do
        payload[:organization_id] = self.repository.organization&.id
        payload[:business_id] = self.repository.organization&.business&.id
      end
      GitHub.instrument("workflow_run.status_changed", payload)
    end
  end

  def expired_workflow_run?
    actions_app? && created_at < 1.month.ago
  end

  def missing_workflow_run?
    workflow_run_is_missing = workflow_run? && workflow_run.nil?
    if workflow_run_is_missing
      GitHub.dogstats.increment("actions.checks.workflow_run_missing.rerequest")
    end
    workflow_run_is_missing
  end

  def disabled_workflow?
    workflow_run? && workflow_run.workflow.disabled?
  end

  def gate_approval_logs_for_execution(execution: nil)
    return gate_approval_logs unless execution.present?
    gate_approval_logs.where("created_at BETWEEN ? and ?", execution.started_at || execution.created_at, execution.completed_at || DateTime.now)
  end

  def notification_recipients
    if send_codespace_prebuild_notification?
      codespace_prebuild_notification_recipients
    else
      [creator].select do |user|
        user && !user.ghost? && !user.bot?
      end
    end
  end

  # We use this method to extract metadata especially from
  # required workflow paths.
  def verify_and_return_workflow_path_metadata(workflow_file_path)
    return workflow_file_path, nil unless workflow_file_path.starts_with?(Actions::Workflow::REQUIRED_WORKFLOWS_BASE_PATH)

    split_file_path = workflow_file_path.split("/")

    # We expect required workflow paths in the following format
    # `required/<source_repo_database_id>/<rest_of_the_path>.yml`
    imposer_repository_id = split_file_path[1].to_i

    # Remove the metadata and just store the path of the
    # workflow from the base directory because we have extracted
    # the necessary fields to identify a required workflow
    split_file_path.slice!(0..1)

    [split_file_path.join("/"), imposer_repository_id]
  end

  # Indicates whether the check_suite is due to a required_workflow run
  def is_required_workflow_run?
    return false unless workflow_run? # has to be of actions integration
    if workflow_run.present?
      workflow_run&.required_workflow_run?
    else  # in-case workflow run is not yet created, fetch from path and validate
      return false unless workflow_file_path = self.workflow_file_path
      _, imposer_repository_id = verify_and_return_workflow_path_metadata(workflow_file_path)
      true if imposer_repository_id.present? && imposer_repository_id > 0
    end
  end

  def imposer_repo_id
    _, imposer_repository_id = verify_and_return_workflow_path_metadata(workflow_file_path)
    imposer_repository_id
  end

  def processed_workflow_file_path
    processed_workflow_file_path, _ = verify_and_return_workflow_path_metadata(workflow_file_path)
    processed_workflow_file_path
  end

  def body
    "The run for #{head_branch} #{conclusion_as_phrase}."
  end
  alias body_html body

  # There is a unique constraint on the check_suites table for repository_id and external_id so any new clones need a slightly different external_id
  # See https://github.com/github/c2c-actions/blob/main/docs/adrs/5554-green-trees.md#maintaining-a-unique-planid
  def new_unique_external_id_for_clone
    "#{external_id}#clone-#{SecureRandom.hex(6)}"
  end

  # For cloned check suites, the first 36 characters of the external_id are original
  def original_actions_external_id
    return unless external_id

    external_id[0..35]
  end

  # For force cancellations in staff tools.
  def force_set_cancellation_state(actor:)
    return unless cancelable?
    return unless workflow_run?

    # Set the check suite to a cancelled state
    update(cancelled_at: Time.zone.now, status: :completed, conclusion: :cancelled)

    check_runs.each do |check_run|
      if !check_run.completed?
        CheckRun.throttle do
          check_run.update(status: :completed, conclusion: :cancelled)
        end
      end
    end

    workflow_run.emit_cancel_audit_log(actor: actor)
  end

  # Force updating the checks data in Dotcom from stafftools introduces the risk of data becoming out of sync with the backend. Cancellations might not work for a bit due to an outage but after a period of time things
  # could work again or postbacks might come in. Runs that are force cancelled too early could have weird consequences like getting billed later for a run that was cancelled but later completes. To account for this risk, force cancelling checks
  # data from stafftools is only allowed if the check suite is older than 1 day.
  def force_set_cancellation_eligible?
    updated_at < 1.day.ago
  end

  def completed_steps_via_results_service?
    (
      !GitHub.enterprise? &&
      !opt_out_from_results? &&
      GitHub.flipper[:fetch_steps_for_run].enabled?(repository) &&
      created_at.year >= 2024
    ) || workflow_run&.is_actions_four_nines_run?
  end

  def opt_out_from_results?
    GitHub.flipper[:actions_opt_out_results_service].enabled?(repository.owner) || GitHub.flipper[:actions_opt_out_results_service].enabled?(repository)
  end

  def steps_from_results(jobs = nil)
    return [] if missing_workflow_run?

    jobs = workflow_run.check_suite.check_runs if jobs.nil?

    # format results request
    run_job_hash = Hash.new
    jobs.each do |job|
      next unless job.is_actions_check_run? && job.check_run_has_steps?
      # using the original workflow run execution (which maps to the workflow_run_external_id) to get the steps in results
      # with four nines runs, we could use the workflow_run_external_id directly, but this is more consistent between three and four nines
      external_run_id = job.workflow_job_run.original_workflow_run_execution.external_id
      run_job_hash[external_run_id] ||= Set.new # initialize if not present
      run_job_hash[external_run_id] << job.external_id # add job to the list of jobs to fetch steps for
    end

    run_job_hash = run_job_hash.transform_values(&:to_a)

    resp = ActionsResults::Twirp.steps_client.get_multiple_workflow_steps(
      run_jobs_map: run_job_hash
    )

    job_step_hash = Hash.new

    if !resp.call_succeeded?
      GitHub.dogstats.increment("actions.workflow_run.steps_from_results", tags: ["status_code:#{resp.status}"])
      GitHub.logger.error("failed to fetch steps from results service", {
        "gh.check_run.status" => status,
        "http.response.status_code" => resp.status,
        "exception.message" => resp.options[:message],
      })
      return job_step_hash
    end

    return job_step_hash if resp.value.job_steps.empty?

    # map the results to the job external_id
    job_steps_map = resp.value.job_steps.each_with_object({}) do |job_steps, hash|
      hash["#{job_steps.workflow_run_backend_id}:#{job_steps.workflow_job_run_backend_id}"] = job_steps
    end

    # hydrate the initial jobs with the steps
    jobs.each do |job|
      external_run_id = job.workflow_job_run.original_workflow_run_execution.external_id
      job_steps = job_steps_map["#{external_run_id}:#{job.external_id}"]
      next unless job_steps
      steps = job_steps.steps.map do |step|
        CheckStep.from_results_step(
          step: step,
          repository_id: self.repository_id,
          check_run_id: job.id
        )
      end

      job_step_hash[job.id] = steps
    end

    job_step_hash
  end

  private

  def conclusion_as_phrase
    case conclusion
    when "success"
      "has succeeded"
    when "failure"
      "has failed"
    when "cancelled"
      "was cancelled"
    when "action_required"
      "requires action"
    when "skipped"
      "was skipped"
    when "timed_out"
      "timed out"
    else
      "has completed"
    end
  end

  def deliver_notifications
    if deliver_notifications?
      GitHub.newsies.trigger(
        CheckSuiteEventNotification.new(self),
        recipient_ids: notification_recipients.map(&:id),
        reason: :ci_activity,
        event_time: updated_at || created_at,
      )
      GlobalInstrumenter.instrument("check_suite.notification_triggered", { check_suite: self, conclusion: conclusion })
    end
  end

  def deliver_notifications?
    workflow_run? &&
      notification_recipients.any? &&
      !merging_upstream_into_fork? &&
      completed_with_conclusion_change?
  end

  # Is the head repo actually the parent of the base repo?
  # If so, this means that we're dealing with changes coming from upstream into
  # a fork. In other words, the base repo is actually a fork of the head repo.
  def merging_upstream_into_fork?
    head_repository_id && (head_repository_id == repository.parent_id)
  end

  def codespace_prebuild_notification_recipients
    configuration_actors_to_notify = Codespaces::PrebuildConfiguration.find_by(latest_workflow_run_id: workflow_run.id)&.actors_to_notify&.to_a
    return [] unless configuration_actors_to_notify.present?

    teams_to_notify_ids = configuration_actors_to_notify.select { |actor| actor.owner_type == "Team" }.map(&:owner_id)
    members_of_teams = Team.members_of(teams_to_notify_ids).limit(1000)

    users_to_notify_ids = configuration_actors_to_notify.select { |actor| actor.owner_type == "User" }.map(&:owner_id)
    users_to_notify = User.where(id: users_to_notify_ids).limit(1000)

    GitHub.logger.info("prebuild notify on failure info",
      {
        "catalog_service" => "github/codespaces",
        "workflow_run_id" => workflow_run.id,
        "prebuild_configuration_id" => configuration_actors_to_notify.first.codespace_prebuild_configuration_id,
        "users_to_notify_count" => users_to_notify_ids.count,
        "teams_to_notify_count" => teams_to_notify_ids.count,
      }
    )

    (members_of_teams + users_to_notify).uniq
  end

  def send_codespace_prebuild_notification?
    workflow_run.present? && workflow_run.codespaces_prebuild_dynamic_workflow_run? && failed?
  end

  def workflow_run?
    actions_app? && GitHub.actions_enabled?
  end

  def is_actions_partial_rerun?(only_failed_check_runs, only_check_run_id)
    (only_failed_check_runs || only_check_run_id) && workflow_run.present?
  end

  def job_ids_for_partial_rerun(check_run_id)
    if check_run_id
      latest_execution = workflow_run.latest_workflow_run_execution

      out = workflow_run.
              workflow_job_runs.
              where(workflow_run_execution_id: latest_execution.id).
              select { |job_run| job_run.check_run.id == check_run_id }.
              map { |job_run| job_run.check_run.external_id }
      raise CheckSuite::ActionsDependency::PreviousJobAttemptError if out.size != 1
      out
    else
      out = workflow_run.failed_workflow_job_runs.map { |job_run| job_run.check_run.external_id }
      raise CheckSuite::NotRerequestableError if out.empty?
      out
    end
  end

  # After a rerun, copy non-Actions check runs from past execution
  def copy_non_actions_check_runs_from_previous_execution
    return unless completed_with_conclusion_change? && workflow_run.present?

    copy_non_actions_check_runs_from_previous_execution_without_conclusion_check
  end

  def copy_non_actions_check_runs_from_previous_execution_without_conclusion_check
    current_execution = workflow_run.latest_workflow_run_execution
    return unless current_execution.present? && current_execution.attempt > 1

    previous_execution = current_execution.previous_execution

    # Do not copy check runs if check run with the same name created in this execution
    current_non_actions_check_run_names = workflow_run.latest_check_runs(execution: current_execution)
                                        .select { |check_run| !check_run.is_actions_check_run? }
                                        .pluck(:name)
                                        .to_set

    previous_non_actions_check_runs_to_copy = workflow_run.latest_check_runs(execution: previous_execution)
                                            .select { |check_run| !check_run.is_actions_check_run? && check_run.completed? && !current_non_actions_check_run_names.include?(check_run.name) }
                                            .map { |check_run| check_run.dup }

    previous_non_actions_check_runs_to_copy.each { |check_run| check_run.update(started_at: completed_at, completed_at: completed_at) }
  end
end
