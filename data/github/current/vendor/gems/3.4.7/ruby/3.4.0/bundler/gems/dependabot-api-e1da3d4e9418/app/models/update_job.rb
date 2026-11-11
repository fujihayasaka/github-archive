# frozen_string_literal: true

require "nullable_serializer"
require "dependabot/experiment"

class UpdateJob < ApplicationRecord # rubocop:disable Metrics/ClassLength
  T.unsafe(self).include Statesman::Adapters::ActiveRecordQueries[
    transition_class: UpdateJobTransition,
    transition_name: :update_job_transition,
    initial_state: :pending
  ]

  MIN_RUN_INTERVAL = Rails.env.development? ? 5.seconds : 1.minute
  MAX_FILE_FETCHER_RUN_TIME = 10.minutes
  MAX_FILE_UPDATER_RUN_TIME = 45.minutes

  P1 = 1
  P2 = 2
  P3 = 3
  P4 = 4

  P1_TRIGGER_TYPES = %w(
    manual_version_update
    manual_rebase
    unknown
    install
    push
    schedule
    rebase
    config_file_changed
  ).freeze

  P2_TRIGGER_TYPES = %w(
    manual
    scan
  ).freeze

  P4_TRIGGER_TYPES = %w(
    graph
  ).freeze

  TRIGGER_TYPES = P1_TRIGGER_TYPES +
                  P2_TRIGGER_TYPES +
                  P4_TRIGGER_TYPES

  PULL_REQUEST_TRIGGER_TYPES_P1 = %w(
    manual
    manual_version_update
    manual_rebase
  ).freeze

  PULL_REQUEST_TRIGGER_TYPES_P2 = %w(
    unknown
    graph
    install
    push
    schedule
    rebase
    config_file_changed
  ).freeze

  PULL_REQUEST_TRIGGER_TYPES_P3 = %w(
    scan
  ).freeze

  SECURITY_TRIGGER_TYPES = %w(manual scan install push).freeze
  SCHEDULED_TRIGGER_TYPES = %w(manual_version_update schedule config_file_changed).freeze
  REBASE_TRIGGER_TYPES = %w(rebase manual_rebase).freeze
  GRAPH_TRIGGER_TYPES = %w(graph).freeze

  TERMINAL_UPDATE_JOB_STATES = %i(processed processed_with_errors timed_out cancelled abandoned
                                  no_successful_runs).freeze

  # Define prefix for job and cred token for Dependabot service to
  # clearly distinguish them during code scanning
  DEPENDABOT_JOB_TOKEN_PREFIX = "dependabot-job_"
  DEPENDABOT_CRED_TOKEN_PREFIX = "dependabot-cred_"

  RUNNER_TYPES = [
    RUNNER_ACTIONS = "actions",
    RUNNER_SELF_HOSTED = "actions_self_hosted",
  ].freeze

  REPORTABLE_EXPERIMENTS = %i(timeout_per_operation_seconds).freeze

  # Normalization mapping for security updates
  # Some ecosystems/package managers share the same advisory database
  ADVISORY_NORMALIZATION_MAPPING = {
    PackageManagers::GRADLE => PackageManagers::MAVEN,
    PackageManagers::CONDA => PackageManagers::PIP,
  }.freeze

  enum :command, { version: 0, security: 1, recreate: 2, graph: 3 }

  belongs_to :update_config

  has_many :update_job_transitions, autosave: false
  has_many :pending_pull_requests
  has_many :pull_requests
  has_many :update_job_errors
  has_many :update_job_unknown_errors
  has_many :update_job_warnings
  has_many :enqueued_together, # rubocop:disable Rails/InverseOf
           -> { where.not(enqueue_scheduled_update_id: nil) },
           class_name: "UpdateJob",
           primary_key: :enqueue_scheduled_update_id,
           foreign_key: :enqueue_scheduled_update_id

  belongs_to :pull_request_transition, optional: true, inverse_of: :update_job

  has_one :repo, through: :update_config

  validates :update_config, presence: true
  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
  validates :runner_type, presence: true, inclusion: { in: RUNNER_TYPES }
  validate :metrics_metadata_is_valid_json_object
  validates :triggered_by_ghsa_id, allow_blank: true,
                                   absence: { unless: :can_be_triggered_by_ghsa? },
                                   format: { with: GitHubSecurityAdvisory::GHSA_ID_REGEX }

  scope :completed,
        -> { in_state(*TERMINAL_UPDATE_JOB_STATES) }

  scope :scheduled,
        -> { where(trigger_type: SCHEDULED_TRIGGER_TYPES) }

  scope :security_updates,
        -> { where(security_updates_only: true) }

  scope :expired,
        -> { where("expires_at < ?", Time.now.in_time_zone) }

  scope :enqueued_together,
        ->(enqueue_scheduled_update_id) { where(enqueue_scheduled_update_id:) }

  delegate :can_transition_to?, :transition_to!, :transition_to, :current_state,
           :last_transition, :history, :in_state?, to: :state_machine
  delegate :config_feature_enabled?, to: :repo, allow_nil: true
  delegate :org_level_flag_enabled?, to: :repo, allow_nil: true
  delegate :repo_level_flag_enabled?, to: :repo, allow_nil: true
  delegate :package_manager, :language, :formatted_language, :directory,
           :target_branch, :custom_labels, :default_labels, :lockfile_only,
           :update_subdependencies?, :default_assignees,
           :default_milestone, :requirements_update_strategy, :allowed_updates,
           :commit_message_prefix, :commit_message_prefix_development,
           :commit_message_include_scope, :accessible_github_repo_ids,
           :multi_ecosystem_config_id, :multi_ecosystem_config,
           to: :update_config

  serialize :initiator_metadata, coder: JSON
  serialize :dependencies, coder: NullableSerializer.new(Array)
  serialize :directories, coder: NullableSerializer.new(Array)

  before_validation :set_default_runner_type, on: :create
  after_commit :update_last_scheduled_job, on: :create, if: :scheduled?

  def unique_errors
    update_job_errors.uniq(&:error_type)
  end

  def completed?
    in_state?(*TERMINAL_UPDATE_JOB_STATES)
  end

  def expired?
    expires_at && expires_at < Time.now.in_time_zone
  end

  def processing_errors
    return [] unless in_state?(:processed_with_errors)

    last_transition.metadata["errors"]
  end

  def relevant_security_advisories
    return [] unless security_updates_only?

    @relevant_security_advisories ||= fetch_security_advisories
  end

  def relevant_security_advisories_hash
    relevant_security_advisories.map do |advisory|
      {
        dependency_name: advisory.dependency_name,
        patched_versions: advisory.native_patched_versions,
        # `unaffected_versions` is unused at present, we pass an empty array in the event we want
        # to inject the unaffected versions from Advisories in future.
        unaffected_versions: [],
        affected_versions: advisory.native_affected_versions,
      }
    end.uniq
  end

  def no_potential_pull_requests?
    pending_pull_requests.none? && pull_requests.none?
  end

  def github_request?
    github_request_id
  end

  def manual?
    trigger_type == "manual"
  end

  def scheduled?
    SCHEDULED_TRIGGER_TYPES.include?(trigger_type)
  end

  def updating_a_pull_request?
    pull_request_transition_id.present?
  end

  def proxy_log_response_body_on_auth_failure?
    config_feature_enabled?(:proxy_log_response_body_on_auth_failure)
  end

  def current_dependency_group
    return unless updating_a_pull_request?
    return update_config.dependency_groups.first if multi_ecosystem_config_id.present?

    pull_request_transition.pull_request.dependency_group
  end

  # NOTE: Git sha ignores are not supported in dependabot-core
  def ignore_conditions_hash
    update_config.ignore_conditions.
      map do |ignore_condition|
        {
          dependency_name: ignore_condition.dependency_name,
          version_requirement: ignore_condition.version_requirement,
          update_types: ignore_condition.update_types,
          source: ignore_condition.source,
          updated_at: ignore_condition.updated_at,
        }
      end
  end

  def multi_ecosystem_siblings
    return self.class.none if multi_ecosystem_config_id.blank?

    self.class.where(update_config_id: update_config.multi_ecosystem_siblings.ids)
  end

  def multi_ecosystem_siblings_enqueued_together
    return self.class.none if enqueue_scheduled_update_id.blank?
    return self.class.none if multi_ecosystem_config_id.blank?

    multi_ecosystem_siblings.enqueued_together(enqueue_scheduled_update_id)
  end

  #######################
  # State machine setup #
  #######################

  def state_machine
    @state_machine ||=
      UpdateJobStateMachine.new(
        self,
        association_name: :update_job_transitions,
        transition_class: UpdateJobTransition
      )
  end

  def increment_metric(name, value = 1, tags: {})
    return if dry_run?

    MetricsClient.count(name, value, tags: job_metric_tags.merge(tags))
  end

  def distribution_metric(name, value, tags: {})
    return if dry_run?

    MetricsClient.distribution(name, value, tags: job_metric_tags.merge(tags))
  end

  def timing_metric(name, duration, tags: {})
    return if dry_run?

    MetricsClient.timing(name, duration, tags: job_metric_tags.merge(tags))
  end

  def retry!(wait: 0)
    transition_to!(:pending_retry)

    # If an update job has any errors or warnings, we consider it to have
    # processed_with_errors, so clean the slate for the next attempt
    UpdateJobError.where(update_job_id: id).delete_all
    UpdateJobWarning.where(update_job_id: id).delete_all
    update!(actions_external_id: nil, actions_workflow_run_id: nil)

    PrioritizedJobs::StartUpdateJob.perform_later(self, wait: wait)
    increment_metric("update_job.retry", tags: job_metric_tags)
  end

  def job_metric_error_category
    # Returning a string value to make it easier to spot issues in datadog as
    # the query group by seems to omit nil values by default
    return "unexpected_job_state" if !in_state?(:processed_with_errors) || unique_errors.empty?

    error_category(error_type: last_error&.error_type)
  end

  def last_error
    unique_errors.last
  end

  def error_category(error_type:) # rubocop:disable Metrics/MethodLength
    case error_type
    when "all_versions_ignored",
         "bad_gitmodules",
         "branch_not_found",
         "config_not_valid",
         "dependency_file_not_evaluatable",
         "dependency_file_not_found",
         "dependency_file_not_parseable",
         "dependency_file_not_resolvable",
         "dependency_not_found",
         "directory_not_found",
         "git_dependency_reference_not_found",
         "git_token_auth_error",
         "go_module_path_mismatch",
         "job_repo_not_found",
         "misconfigured_tooling",
         "open_pull_request_limit_exceeded",
         "path_dependencies_not_reachable",
         "pull_request_exists_for_latest_version",
         "registry_error",
         "secret_not_found",
         "secret_not_valid",
         "self_hosted_runner_unavailable",
         "unexpected_external_code",
         "unresolvable_version"
      "user_error"
    when "cancelled_update",
         "dependency_file_content_not_changed",
         "dependency_file_not_supported",
         "edited_pull_request_exists",
         "file_fetcher_error",
         "git_dependencies_not_reachable",
         "missing_environment_variable",
         "no_potential_pull_request", # deprecated error
         "private_source_authentication_failure",
         "private_source_bad_response",
         "private_source_certificate_failure",
         "private_source_not_reachable",
         "private_source_timed_out",
         "pull_request_creation_halted",
         "pull_request_exists_for_security_update",
         "security_update_dependency_not_found",
         "security_update_not_found",
         "security_update_not_needed",
         "security_update_not_possible",
         "tool_feature_not_supported",
         "tool_version_not_supported",
         "transitive_update_not_possible",
         "unknown_no_potential_pull_request", # deprecated error
         "update_files_error",
         "update_graph_error",
         "update_not_possible"
      "expected_error"
    when "actions_service_failed",
         "actions_service_repository_not_found",
         "actions_service_unavailable",
         "actions_service_unknown",
         "actions_service_unprocessable",
         "actions_workflow_image",
         "actions_workflow_unknown",
         "actions_workflow_updater",
         "internal_pull_request_creation_failure",
         "octokit_rate_limited",
         "octokit_unauthorized",
         "out_of_disk",
         "out_of_memory",
         "pull_request_creation_failure",
         "resource_unavailable_to_installation",
         "runner_error",
         "timed_out",
         "unknown_error"
      "unexpected_error"
    else
      "unrecognized_error"
    end
  end

  # TODO: Set this dynamically based on type and ecosystem
  #
  # Used when setting expires_at in UpdateJobStateMachine when transitioning to
  # processing
  def max_run_time
    # Determine how long jobs can run, with padding to account for update runner
    # backoffs + retries.
    #
    max_total_run_time = MAX_FILE_FETCHER_RUN_TIME + max_updater_run_time
    max_backoff = 600.seconds
    # Backoffs are determined in github/dependabot-update-job-runner:
    # backoff: varies between queues: 60, 600, 600
    # > https://github.com/github/composer/blob/ac57dc9fe16c9364e1620549a715f2cebdc53e39/modules/applications/deltaforce/variables.tf#L83

    max_total_run_time +    # First attempt
      max_backoff +         # Backoff after first failure
      max_total_run_time +  # Second attempt
      (max_backoff * 2) +   # Exponential backoff after second failure
      max_total_run_time    # Final attempt
  end

  def max_updater_run_time_cache_key
    [update_config.cache_key, "max_updater_run_time"].join("/")
  end

  def actions_job_timeout_minutes
    return 1 if config_feature_enabled?(:actions_timeout_1_minute)
    return 180 if config_feature_enabled?(:actions_long_timeout)

    (MAX_FILE_FETCHER_RUN_TIME + max_updater_run_time).in_minutes
  end

  def max_updater_run_time
    [
      Rails.cache.fetch(max_updater_run_time_cache_key).to_i,
      MAX_FILE_UPDATER_RUN_TIME,
    ].compact.max
  end

  def experiments # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    {
      grouped_updates_experimental_rules: config_feature_enabled?(:grouped_updates_experimental_rules),
      shared_workspace: config_feature_enabled?(:shared_workspace),
      timeout_per_operation_seconds: config_feature_enabled?(:timeout_per_operation) ? 600 : nil,
      # `record_ecosystem_versions`` is an updater option that we always set on cloud, but never on GHES...
      # It's currently implemented as an experiment flag for GHES backwards compatibility reasons
      # (dependabot-core/pull/7516) and because there are no easy hooks for "updater options". Long term once the
      # backwards compatibility concerns are gone, if there are multiple "updater options based on the environment it's
      # running in", then we should extract those out separately to avoid confusion with *actual* experiments.
      record_ecosystem_versions: !Dependabot.enterprise?,
      # `record_update_job_unknown_error` is a feature flag which is always set on cloud but never on GHES
      # because older GHES versions does not support reporting unknown errors
      record_update_job_unknown_error: !Dependabot.enterprise?,
      proxy_cached: config_feature_enabled?(:proxy_cached),
      threaded_metadata: config_feature_enabled?(:threaded_metadata_updates),
      dependency_change_validation: config_feature_enabled?(:dependency_change_validation),
      dependency_has_directory: config_feature_enabled?(:dependency_has_directory),
      enable_pnpm_yarn_dynamic_engine: config_feature_enabled?(:enable_pnpm_yarn_dynamic_engine),
      enable_file_parser_python_local: config_feature_enabled?(:enable_file_parser_python_local),
      npm_fallback_version_above_v6: config_feature_enabled?(:npm_fallback_version_above_v6),
      enable_record_ecosystem_meta: config_feature_enabled?(:enable_record_ecosystem_meta),
      enable_corepack_for_npm_and_yarn: config_feature_enabled?(:enable_corepack_for_npm_and_yarn),
      enable_private_registry_for_corepack: config_feature_enabled?(:enable_private_registry_for_corepack),
      enable_shared_helpers_command_timeout: config_feature_enabled?(:enable_shared_helpers_command_timeout),
      enable_beta_ecosystems: beta_ecosystems_enabled?,
      enable_dependabot_setting_up_cronjob: config_feature_enabled?(:enable_dependabot_setting_up_cronjob),
      enable_engine_version_detection: config_feature_enabled?(:enable_engine_version_detection),
      avoid_duplicate_updates_package_json: config_feature_enabled?(:avoid_duplicate_updates_package_json),
      allow_refresh_for_existing_pr_dependencies: config_feature_enabled?(:allow_refresh_for_existing_pr_dependencies),
      allow_refresh_group_with_all_dependencies: config_feature_enabled?(:allow_refresh_group_with_all_dependencies),
      exclude_local_composer_packages: config_feature_enabled?(:exclude_local_composer_packages),
      enable_enhanced_error_details_for_updater: config_feature_enabled?(:enable_enhanced_error_details_for_updater),
      enhanced_grouped_security_error_reporting: config_feature_enabled?(:enhanced_grouped_security_error_reporting),
      gradle_lockfile_updater: config_feature_enabled?(:gradle_lockfile_updater),
      gradle_wrapper_updater: config_feature_enabled?(:gradle_wrapper_updater),
      enable_exclude_paths_subdirectory_manifest_files:
        config_feature_enabled?(:enable_exclude_paths_subdirectory_manifest_files),
      group_membership_enforcement: config_feature_enabled?(:group_membership_enforcement),
      deprecate_close_command: config_feature_enabled?(:deprecate_close_command),
      deprecate_reopen_command: config_feature_enabled?(:deprecate_reopen_command),
      deprecate_merge_command: config_feature_enabled?(:deprecate_merge_command),
      deprecate_cancel_merge_command: config_feature_enabled?(:deprecate_cancel_merge_command),
      deprecate_squash_merge_command: config_feature_enabled?(:deprecate_squash_merge_command),
      disable_close_command: config_feature_enabled?(:disable_close_command),
      disable_reopen_command: config_feature_enabled?(:disable_reopen_command),
      disable_merge_command: config_feature_enabled?(:disable_merge_command),
      disable_cancel_merge_command: config_feature_enabled?(:disable_cancel_merge_command),
      disable_squash_merge_command: config_feature_enabled?(:disable_squash_merge_command),
      enable_oidc_auth: config_feature_enabled?(:enable_oidc_auth),
    }.merge(go_module_configuration).
      select { |_, v| v }
  end

  # subset of experiments to persist in the database for analysis
  def reportable_experiments
    experiments.slice(*REPORTABLE_EXPERIMENTS)
  end

  def go_module_configuration
    return {} unless update_config&.package_manager == PackageManagers::GO_MODULES

    if update_config.registries.any?
      { goprivate: "*" }
    elsif repo&.private?
      hostname = Dependabot::Application.target_github_hostname(repo.account)
      { goprivate: "#{hostname}/#{repo.account.github_login}/*" }
    else
      { goprivate: "" }
    end
  end

  def staging_enabled_on_repo?
    # job_sqs_stage controls runner environment (stage vs prod)
    config_feature_enabled?(:job_sqs_stage)
  end

  def runner_environment
    staging_enabled_on_repo? ? "stage" : "prod"
  end

  def cancel!(reason:)
    transition_to!(:cancelled)

    increment_metric(
      "update_job.cancelled",
      tags: {
        cancellation_reason: reason,
        config_file: update_config.using_config_file?,
      }
    )

    NotifyGitHubOfFailureJob.perform_later(
      update_job: self,
      error_hash: {
        "error-type" => "cancelled_update",
        "error-detail" => { "cancellation-reason" => reason },
      },
    )
  rescue Statesman::TransitionFailedError
    raise unless in_state?(:cancelled)
  end

  def actions?
    # All update jobs run on GitHub Actions (both RUNNER_ACTIONS and RUNNER_SELF_HOSTED)
    true
  end

  def self_hosted?
    runner_type == RUNNER_SELF_HOSTED
  end

  def telemetry_attributes
    update_config.telemetry_attributes.merge(
      "gh.dependabot_api.update_job.id": id,
      "gh.dependabot_api.update_job.runner_type": runner_type,
    ).tap do |attrs|
      attrs["gh.actions.workflow_run.id"] = actions_workflow_run_id if actions?

      # Add group-specific context for enhanced observability
      if dependency_groups.any?
        attrs["gh.dependabot_api.update_job.grouping_requested"] = true
        attrs["gh.dependabot_api.update_job.dependency_groups_count"] = dependency_groups.size
        if current_dependency_group
          attrs["gh.dependabot_api.update_job.current_group_name"] = current_dependency_group.name
          attrs["gh.dependabot_api.update_job.current_group_applies_to"] = current_dependency_group.applies_to
        end
      end

      # Add multi-ecosystem context
      if multi_ecosystem_update?
        attrs["gh.dependabot_api.update_job.multi_ecosystem_update"] = true
        attrs["gh.dependabot_api.update_job.multi_ecosystem_config_id"] = multi_ecosystem_config_id
        attrs["gh.dependabot_api.update_job.enqueue_scheduled_update_id"] = enqueue_scheduled_update_id
      end
    end
  end

  def set_runner_type(repository_settings:)
    return if runner_type_changed?

    # Dependabot now always runs on GitHub Actions—either using RUNNER_SELF_HOSTED
    # (if self-hosted is enabled) or RUNNER_ACTIONS (default).
    self_hosted_enabled = repository_settings && repository_settings.dependabot_self_hosted_enabled

    self.runner_type = self_hosted_enabled ? RUNNER_SELF_HOSTED : RUNNER_ACTIONS
  end

  def grouping_requested?
    if security_updates_only?
      dependency_groups.any? || repo.settings.grouped_security_updates_enabled?
    else
      dependency_groups.any?
    end
  end

  def dependency_groups
    if security_updates_only?
      update_config.dependency_groups.select(&:applies_to_security_updates?)
    else
      update_config.dependency_groups.reject(&:applies_to_security_updates?)
    end
  end

  def fallback_dependency_group
    FallbackDependencyGroup.new(name: package_manager)
  end

  # A job must be in processing to proceed to processed_with_errors, but we may have
  # a runner failure while the job remains in a pending or enqueued state.
  #
  # This method just advanced through the intermediate states so we can proceed.
  def ensure_job_is_processing
    transition_to!(:enqueued) if current_state == "pending"
    transition_to!(:processing) if current_state == "enqueued"
  end

  def beta_ecosystems_enabled?
    update_config&.enable_beta_ecosystems? || config_feature_enabled?(:enable_beta_ecosystems)
  end

  def multi_ecosystem_update?
    @multi_ecosystem_update ||= multi_ecosystem_config_id.present? && enqueue_scheduled_update_id.present?
  end

  # Group-specific helper methods for metrics
  def groups?
    dependency_groups.any?
  end

  def group_count
    dependency_groups.size
  end

  def group_names
    dependency_groups.pluck(:name).join(",")
  end

  private

  def parsed_metrics_metadata
    return {} unless metrics_metadata

    @parsed_metrics_metadata ||= if metrics_metadata.is_a? Hash
                                   metrics_metadata
                                 else
                                   JSON.parse(metrics_metadata)
                                 end
  end

  def metrics_metadata_is_valid_json_object
    return true if parsed_metrics_metadata.is_a?(Hash)

    errors.add(:metrics_metadata, "must be a JSON object")
    false
  rescue JSON::ParserError
    errors.add(:metrics_metadata, "must be valid JSON")
    false
  end

  def can_be_triggered_by_ghsa?
    return true if trigger_type.to_s == "unknown"

    SECURITY_TRIGGER_TYPES.include? trigger_type.to_s
  end

  def job_metric_tags
    @job_metric_tags ||= {
      package_manager: package_manager_tag,
      trigger: trigger_type,
      update_type: update_type_tag,
      runner_type: runner_type,
      cooldown: cooldown_meta,
      multi_ecosystem_update: multi_ecosystem_update?,
      grouped_update: groups?,
      group_count: group_count,
    }.tap do |tags|
      # Only add group_names if there are groups to avoid high cardinality
      tags[:group_names] = group_names if groups? && group_count <= 5
    end
  end

  # Insure we access update_config in a nil-safe way
  def package_manager_tag
    update_config&.package_manager || "unknown"
  end

  def cooldown
    update_config&.cooldown
  end

  def cooldown_meta # rubocop:disable Metrics/PerceivedComplexity
    return {} if update_config&.cooldown.nil?

    Rails.logger.info("Initializing cooldown meta #{update_config&.cooldown}") if update_config&.cooldown

    cooldown = update_config&.cooldown

    { "cooldown.package_manager" => update_config&.package_manager || "unknown",
      "cooldown.default_days" => cooldown.fetch("default-days", 0),
      "cooldown.semver_major_days" => cooldown.fetch("semver-major-days", 0),
      "cooldown.semver_minor_days" => cooldown.fetch("semver-minor-days", 0),
      "cooldown.semver_patch_days" => cooldown.fetch("semver-patch-days", 0), }
  rescue StandardError => e
    Rails.logger.info("Error parsing cooldown meta #{e.message}")
    {}
  end

  def update_type_tag
    security_updates_only? ? "security" : "version"
  end

  def set_default_runner_type
    return if runner_type_changed?

    # Dependabot now always runs on GitHub Actions
    self.runner_type = RUNNER_ACTIONS
  end

  def update_last_scheduled_job
    update_config.update(last_scheduled_job_id: id)
  end

  def fetch_security_advisories
    normalized_package_manager = ADVISORY_NORMALIZATION_MAPPING[package_manager] || package_manager

    increment_metric("update_job.fetch_security_advisories")

    start = Time.now.in_time_zone
    response = GitHubSecurityAdvisory.fetch(normalized_package_manager, dependencies)
    duration = Time.now.in_time_zone - start

    timing_metric("update_job.fetch_security_advisories.time", duration)

    response
  end
end
