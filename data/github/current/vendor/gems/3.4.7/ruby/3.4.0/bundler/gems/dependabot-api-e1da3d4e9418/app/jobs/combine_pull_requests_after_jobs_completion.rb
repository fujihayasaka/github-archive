# frozen_string_literal: true

class CombinePullRequestsAfterJobsCompletion < ApplicationJob # rubocop:disable Metrics/ClassLength
  # This job combines multiple pending pull requests into a single pull request
  # after all associated update jobs have completed.
  #
  # It is designed to handle multi-ecosystem updates where multiple update jobs
  # may be associated with a single pull request.
  #
  # The job will create a combined pending pull request if all associated update
  # jobs are in the :processed state. If any job is not complete, it will either
  # reschedule or fail.
  #
  # If an existing pull request is in the :updating state, it will update that
  # pull request instead of creating a new one.
  class NoMatchingUpdateJobError < StandardError; end

  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  RETRY_CONFIG = ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      base_interval: 2.minutes
    ),
    retryable_exceptions: [
      *GitHubHelpers::RETRYABLE_ERRORS,
      Octokit::Unauthorized,
    ],
  )

  include RETRY_CONFIG

  def perform(associated_update_job_ids:)
    @update_job_ids = associated_update_job_ids

    log_progress(msg: "Starting CombinePullRequestsAfterJobsCompletion job")
    log_group_combination_context

    return skip_incomplete_jobs unless all_jobs_complete?

    unless all_jobs_successfully_processed?
      log_progress(msg: "Not all jobs successfully processed, canceling updating PRs")
      cancel_updating_prs
      increase_metric("combine_pull_request.failed", tags: { reason: "not_all_jobs_successful" })
      return
    end

    increase_metric("combine_pull_request.start")

    pending_prs = PendingPullRequest.where(update_job_id: update_job_ids)
    log_pr_combination_attempt(pending_prs)

    return handle_empty_pending_prs if pending_prs.empty?

    process_pr_combination(pending_prs)
  rescue StandardError => e
    handle_combination_failure(e)
    raise
  end

  private

  attr_reader :update_job_ids

  def skip_incomplete_jobs
    increase_metric("combine_pull_request.skipped", tags: { reason: "incomplete_jobs" })
  end

  def handle_empty_pending_prs
    increase_metric("combine_pull_request.failed", tags: { reason: "no_pending_prs" })
  end

  def process_pr_combination(pending_prs)
    primary_pending_pr = if updating_a_pr?
                           increase_metric("combine_pull_request.update_existing_pr")
                           prepare_for_updating_an_existing_pr_on_github(pending_prs)
                         else
                           increase_metric("combine_pull_request.create_new_pr")
                           pending_prs.first
                         end
    if primary_pending_pr.nil?
      log_warning(
        msg: "Primary pending PR is nil, cannot proceed.",
        update_job_ids: update_job_ids,
      )
      increase_metric("combine_pull_request.failed", tags: { reason: "no_primary_pending_pr" })
      return
    end

    combined_pr = create_combined_pr(primary_pending_pr, pending_prs)
    create_pull_request_on_github(combined_pr)

    pending_prs.reject { |pr| pr.id == combined_pr.id }.each(&:destroy!)

    increase_metric("combine_pull_request.success")
  end

  def handle_combination_failure(error)
    increase_metric("combine_pull_request.failed", tags: { reason: "exception", error_type: error.class.name })
  end

  def create_pull_request_on_github(pending_pr)
    log_progress(
      msg: "Creating pull request on GitHub",
      pending_pr_id: pending_pr.id,
    )
    PrioritizedJobs::CreatePullRequestOnGitHub.perform_later(pending_pr: pending_pr)
  end

  def prepare_for_updating_an_existing_pr_on_github(combined_prs)
    # If multiple PRs are in the :updating state, log a warning and exit
    if existing_prs_in_updating_state.size > 1
      log_multiple_updating_prs
      return
    end

    # Ensure the update_config_id matches the one from the PR in the updating state
    existing_pr_in_updating_state = existing_prs_in_updating_state.first
    update_job_id = existing_pr_in_updating_state.last_transition.update_job_id

    log_no_matching_update_job_error(existing_pr_in_updating_state) unless update_jobs.ids.include?(update_job_id)

    # select the combined PR that matches the update_job_id linked to the PR we are :updating
    combined_pr = combined_prs.find { |pr| pr.update_job_id == update_job_id }

    log_progress(
      msg: "Found existing updating PR, updating it with the combined PR",
      existing_pr_in_updating_state_id: existing_pr_in_updating_state.id,
      combined_pr_id: combined_pr.id,
    )

    combined_pr
  end

  def log_no_matching_update_job_error(existing_pr_in_updating_state)
    log_progress(
      msg: "No matching update job found for existing PR in updating state",
      existing_pr_in_updating_state_id: existing_pr_in_updating_state.id,
    )
    increase_metric("combine_pull_request.no_matching_update_job_error")
    raise NoMatchingUpdateJobError,
          "No update job found for existing PR in updating state: #{existing_pr_in_updating_state.id}"
  end

  def updating_a_pr?
    existing_prs_in_updating_state.any?
  end

  def existing_prs_in_updating_state
    @existing_prs_in_updating_state ||=
      PullRequest.where(update_config_id: update_config_ids).select { |pr| pr.in_state?(:updating) }
  end

  def update_jobs
    @update_jobs ||= UpdateJob.where(id: update_job_ids)
  end

  def update_config_ids
    @update_config_ids ||= update_jobs.pluck(:update_config_id)
  end

  def multi_ecosystem_config
    @multi_ecosystem_config ||= update_jobs.first.multi_ecosystem_config
  end

  def log_multiple_updating_prs
    log_warning(
      msg: "Multiple updating PRs found for the same update config",
      existing_prs_count: existing_prs_in_updating_state.size,
    )
    increase_metric("combine_pull_request.multiple_updating_prs")
    increase_metric("combine_pull_request.failed", tags: { reason: "multiple_updating_prs" })
  end

  def all_jobs_complete?
    check_all_jobs_in_states(
      states: UpdateJob::TERMINAL_UPDATE_JOB_STATES,
      description: "complete",
      warning_metric: "combine_pull_request.incomplete_jobs_warning"
    )
  end

  # @param pending_prs [Array<PullRequest>]
  #   An array of pull request objects that are pending and need to be combined into a single pull request.
  def create_combined_pr(primary_pending_pr, pending_prs)
    combined_message_data = build_combined_message_data(pending_prs)
    combined_updated_dependency_details = collect_updated_dependency_details(pending_prs)
    combined_encrypted_dependency_files_blob = build_combined_encrypted_blob(pending_prs)

    increase_package_manager_tags(update_job_ids)
    update_pending_pr_with_combined_data(
      pending_pull_request: primary_pending_pr,
      combined_updated_dependency_details:,
      combined_message_data:,
      combined_encrypted_dependency_files_blob:,
    )
  end

  def update_pending_pr_with_combined_data(pending_pull_request:, combined_updated_dependency_details:,
                                           combined_message_data:, combined_encrypted_dependency_files_blob:)
    pending_pull_request.update!(updated_dependency_details: combined_updated_dependency_details)
    pending_pull_request.message_data = combined_message_data
    attach_encrypted_files_blob(pending_pull_request, combined_encrypted_dependency_files_blob)
    log_combined_pr_creation(pending_pull_request)

    pending_pull_request
  end

  def attach_encrypted_files_blob(combined_pending_pr, blob_content)
    combined_pending_pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(blob_content),
      filename: combined_pending_pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
  end

  def log_combined_pr_creation(combined_pending_pr)
    log_progress(
      msg: "Successfully created combined PR",
      combined_pr_id: combined_pending_pr.id,
    )
  end

  def build_combined_message_data(pending_prs)
    commit_messages = pending_prs.map { |pr| pr.message_data["commit_message"] }
    pr_bodies = pending_prs.map { |pr| pr.message_data["pr_body"] }

    {
      commit_message: commit_messages.join("\n"),
      pr_title: "Bump the \"#{multi_ecosystem_config.name}\" group with " \
                "#{pending_prs.size} updates across multiple ecosystems",
      pr_body: pr_bodies.join("\n"),
    }
  end

  def collect_updated_dependency_details(pending_prs)
    pending_prs.flat_map(&:updated_dependency_details)
  end

  def build_combined_encrypted_blob(pending_prs)
    combined_data = pending_prs.flat_map do |pr|
      decrypted_data = JSON.parse(decrypt(pr.encrypted_dependency_files_blob.download))
      decrypted_data
    end
    encrypt(combined_data.to_json)
  end

  def encrypt(json)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(json))
  end

  def decrypt(encrypted_data)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    decryption_box = RbNaCl::SimpleBox.from_secret_key(token)

    decrypted_data = decryption_box.decrypt(Base64.strict_decode64(encrypted_data))
    decrypted_data.force_encoding("UTF-8")
  end

  def increase_package_manager_tags(update_job_ids)
    update_jobs = UpdateJob.where(id: update_job_ids)
    tags = update_jobs.map { |uj| uj.package_manager || "unknown" }.uniq.sort

    tags.each do |tag|
      increase_metric("ecosystem", tags: { package_manager: tag })
    end

    increase_metric("ecosystem.combined", tags: { package_managers: tags })
  end

  def increase_metric(name, tags: {})
    # Get group context from first update job (all jobs in the combination should have the same groups)
    first_job = update_jobs.first
    group_tags = if first_job&.groups?
                   {
                     grouped_update: true,
                     group_count: first_job.group_count,
                     group_names: first_job.group_names,
                   }
                 else
                   {
                     grouped_update: false,
                     group_count: 0,
                   }
                 end

    MetricsClient.increment("multi_ecosystem.#{name}", tags: tags.merge(group_tags))
  end

  def log_progress(params)
    Dependabot::Logger.info(**base_log_params, **params)
  end

  def log_warning(params)
    Dependabot::Logger.warn(**base_log_params, **params)
  end

  def base_log_params
    {
      at: "CombinePullRequestsAfterJobsCompletion",
      associated_update_job_ids: update_job_ids,
      associated_update_job_count: update_job_ids.length,
      associated_update_config_count: multi_ecosystem_siblings_size,
      multi_ecosystem_config_name: multi_ecosystem_config.name,
      multi_ecosystem_config_id: multi_ecosystem_config.id,
    }
  end

  def multi_ecosystem_siblings_size
    @multi_ecosystem_siblings_size ||= UpdateJob.find(update_job_ids.first).update_config.multi_ecosystem_siblings.size
  end

  def log_group_combination_context
    # Log detailed context about the group combination process
    log_progress(
      msg: "Group combination context",
      update_jobs_status: update_jobs.map do |job|
        {
          id: job.id,
          state: job.current_state,
          grouping_requested: job.grouping_requested?,
          dependency_groups_count: job.dependency_groups.size,
          multi_ecosystem_update: job.multi_ecosystem_update?,
        }
      end,
      multi_ecosystem_update_config_siblings_count: multi_ecosystem_config&.update_config_siblings&.size || 0,
    )
  end

  def log_pr_combination_attempt(pending_prs)
    # Log details about the PR combination attempt for debugging silent failures
    log_progress(
      msg: "Attempting to combine PRs for group update",
      pending_prs_count: pending_prs.size,
      pending_pr_details: pending_prs.map do |pr|
        {
          id: pr.id,
          update_job_id: pr.update_job_id,
          has_dependency_files: pr.encrypted_dependency_files_blob.attached?,
          message_data_keys: pr.message_data&.keys || [],
        }
      end
    )

    # Log warning if no pending PRs found
    return unless pending_prs.empty?

    log_warning(
      msg: "No pending PRs found for group combination",
      potential_silent_failure: true
    )
    increase_metric("combine_pull_request.no_pending_prs_warning")
  end

  def all_jobs_successfully_processed?
    check_all_jobs_in_states(
      states: [:processed],
      description: "successfully processed",
      warning_metric: "combine_pull_request.failed_jobs_warning"
    )
  end

  def check_all_jobs_in_states(states:, description:, warning_metric:)
    matching_jobs = update_jobs.select { |job| job.in_state?(*states) }
    all_match = matching_jobs.size == update_jobs.size

    unless all_match
      increase_metric(warning_metric)
      log_warning(
        msg: "Not all jobs are #{description}",
        total_jobs: update_jobs.size,
        matching_jobs: matching_jobs.size,
        job_states: update_jobs.map(&:current_state)
      )
    end

    all_match
  end

  def cancel_updating_prs
    return if existing_prs_in_updating_state.empty?

    log_progress(
      msg: "Canceling updating PRs due to failed jobs in group",
      updating_prs_count: existing_prs_in_updating_state.size,
      pr_ids: existing_prs_in_updating_state.map(&:id)
    )

    existing_prs_in_updating_state.each { |pull_request| cancel_single_updating_pr(pull_request) }
  end

  def cancel_single_updating_pr(pull_request)
    update_job_id = pull_request.last_transition&.update_job_id
    update_job = update_jobs.find { |job| job.id == update_job_id }

    if should_cancel_pr?(pull_request, update_job)
      schedule_pr_cancellation(pull_request, update_job)
    else
      log_pr_cancellation_skip(pull_request, update_job_id, update_job)
    end
  end

  def should_cancel_pr?(pull_request, update_job)
    update_job && pull_request.last_transition&.most_recent?
  end

  def schedule_pr_cancellation(pull_request, update_job)
    log_progress(
      msg: "Scheduling CancelStalePullRequestUpdate for PR",
      pr_id: pull_request.id,
      update_job_id: update_job.id
    )
    CancelStalePullRequestUpdate.perform_later(update_job: update_job)
    increase_metric("combine_pull_request.cancel_updating_pr")
  end

  def log_pr_cancellation_skip(pull_request, update_job_id, update_job)
    log_warning(
      msg: "Could not find update job for updating PR or transition not most recent",
      pr_id: pull_request.id,
      last_transition_update_job_id: update_job_id,
      has_update_job: update_job.present?,
      is_most_recent: update_job&.pull_request_transition&.most_recent?
    )
  end
end
