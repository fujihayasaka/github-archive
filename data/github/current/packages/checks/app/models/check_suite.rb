# typed: true
# frozen_string_literal: true

require "github-launch"

class CheckSuite < ApplicationRecord::Domain::RepositoriesActionsChecks
  self.ignored_columns = %w(action)

  class NotRerequestableError < StandardError; end
  class AlreadyRerunningError < NotRerequestableError; end
  class DisabledWorkflowError < NotRerequestableError; end
  class MissingWorkflowRunError < NotRerequestableError; end
  class ExpiredLogsError < NotRerequestableError; end

  include GitHub::Memoizer
  include GitHub::Relay::GlobalIdentification
  include GitHub::Tracing
  include Instrumentation::Model
  include CheckSuite::ActionsDependency
  include ChecksRollupHelper
  include Checks::RepositorySharding
  include Repositories::Domain::Provider

  configure_sharding(should_shard: -> (_, operation) {
    [:save, :save!].include?(operation) # Only enabling sharding key for save operation
  })

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::CheckSuite

  attribute :head_branch, StringFromBinary.new
  attribute :name, StringFromBinary.new
  attribute :action, StringFromBinary.new
  attribute :workflow_file_path, StringFromBinary.new
  attribute :is_archived, :boolean, default: false

  # check_run with gates can last for 30 days
  DEFAULT_STALE_THRESHOLD = 31.days

  # Amount of check suites that are displayed on the checks page when looking at an individual check run
  MOST_RECENT_CHECK_SUITE_LIMIT = 25

  belongs_to :creator, class_name: "User"
  belongs_to :repository
  destroy_in_background_with :repository,
    cross_shard_query_exempted: true,
    deletion_stage: GitHub::BackgroundDeletes::DeletionStage::RepositorySoftDelete
  belongs_to :github_app, class_name: "Integration"
  belongs_to :head_repository, class_name: "Repository"

  has_many :check_runs, inverse_of: :check_suite
  destroy_dependents_in_background :check_runs, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :artifacts, inverse_of: :check_suite
  destroy_dependents_in_background :artifacts, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :annotations, class_name: "CheckAnnotation", inverse_of: :check_suite
  destroy_dependents_in_background :annotations, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_one :workflow_run, class_name: "Actions::WorkflowRun", inverse_of: :check_suite
  has_many :gate_approval_logs, -> { order "id DESC" }, inverse_of: :check_suite
  has_one :code_scanning_check_suite, ->(check_suite) { where(repository_id: check_suite.repository_id) }, dependent: :destroy, inverse_of: :check_suite

  validates_presence_of :github_app_id
  validates_presence_of :repository_id
  validates_presence_of :head_sha
  validates_length_of :external_id, maximum: 64

  after_commit :instrument_completion
  after_create :create_workflow_run
  after_commit :instrument_workflow_run_create, on: :create
  before_save :instrument_status_changed
  after_save :synchronize_workflow_run
  before_create :calculate_hidden_flag
  before_create :set_started_at
  before_destroy :delete_logs_from_file_storage, if: :actions_app?
  before_destroy :delete_artifacts_from_actions_service, if: :actions_app?
  before_save :set_uniqueness_key

  after_commit :update_workflow_run_execution, on: [:update], if: :status_previously_changed?
  after_commit :deliver_workflow_run_complete_notifications, on: [:update]
  after_commit :deliver_notifications, on: [:create, :update]
  after_commit :copy_non_actions_check_runs_from_previous_execution, on: [:update]
  after_save_commit :measure_completion
  after_commit :notify_socket_subscribers, on: [:update], if: :should_notify_socket_subscribers_of_update?

  trace_method :synchronize_workflow_run
  trace_method :update_workflow_run_execution
  trace_method :deliver_workflow_run_complete_notifications
  trace_method :deliver_notifications
  trace_method :copy_non_actions_check_runs_from_previous_execution
  trace_method :notify_socket_subscribers
  trace_method :create_workflow_run
  trace_method :set_rollup_values!
  trace_method :instrument_completion
  trace_method :request
  trace_method :event_payload

  scope :for_ids, ->(ids) { where(id: ids) }
  scope :for_app_id, ->(id) { where(github_app_id: id) }
  scope :for_app_ids, ->(*ids) { where(github_app_id: ids) }
  scope :group_by_name, -> { group(:name) }
  scope :with_check_run_named, ->(name, repo_id) {
    joins("INNER JOIN check_runs ON check_runs.check_suite_id = check_suites.id").
    where("check_runs.name = ? AND check_runs.repository_id = ?", name, repo_id)
  }
  scope :most_recent, -> { order("id DESC").limit(MOST_RECENT_CHECK_SUITE_LIMIT) }
  scope :incomplete_and_older_than_stale_threshold, -> (start_time: Time.now) {
    where(conclusion: nil).where("created_at < ?", start_time - DEFAULT_STALE_THRESHOLD)
  }

  # These statuses are being used by git-src-migrator to monitor the status of dynamic workflows in
  # app/api/internal/twirp/git_src_migrator/monolith/v1/git_src_migrator_workflow_api_handler.rb
  # Please let the Migration Tools team know if you add/remove any statuses
  enum :status, CheckRun.statuses
  enum :conclusion, CheckRun.conclusions.merge(startup_failure: 8)

  delegate :name, to: :github_app, prefix: true
  delegate :action, :trigger, to: :workflow_run, allow_nil: true
  delegate :check_suite, :run_number, to: :workflow_run

  T.unsafe(self).alias_method :entity, :repository
  T.unsafe(self).alias_method :async_entity, :async_repository

  attr_accessor :workflow_run_data, :skip_update_workflow_run_execution, :skip_delete_resources_from_launch

  def self.request(repository:, head_sha:, actor:)
    installations_with_access = IntegrationInstallation.with_resources_on(subject: repository, resources: "checks", min_action: :write)
    return if installations_with_access.blank?

    push = Repositories::Domain.new.pushes.by_repo_id_and_after(after: head_sha, repository_id: repository.id)


    installations_with_access.each do |installation|
      next unless repository.auto_trigger_checks_for?(app_id: installation.integration_id)

      attrs = {
        github_app_id: installation.integration_id,
        head_sha: head_sha,
        repository_id: repository.id,
      }

      existing_check_suite = CheckSuite.find_by(attrs)
      return if existing_check_suite

      attrs.merge!(
        head_branch: push&.branch_name,
        push_id: push&.id,
      )
      check_suite = CheckSuite.create!(attrs)
      check_suite.request(actor: actor)
    end
  end

  def self.find_or_create_for_integrator(attrs)
    record = new(attrs)

    repo = T.must(record.repository)
    if record.external_id.present?
      existing = repo.check_suites.where(
        external_id: record.external_id,
        github_app_id: record.github_app.id,
      ).first

      if existing
        GitHub.dogstats.increment("checks.create_check_suite.suite_with_external_id_already_exists")
        return IntegratorCreateResult.new(existing, existing: true)
      end
    end

    if !record.github_app.multiple_check_suites_per_sha_enabled?
      same_sha = repo.check_suites.where(
        uniqueness_key: record.head_sha,
        github_app_id: record.github_app.id,
      ).exists?

      if same_sha
        record.errors.add(:head_sha, IntegratorCreateResult::DUPLICATE_SHA_MESSAGE)
        return IntegratorCreateResult.new(record)
      end
    end

    if record.github_app.multiple_check_suites_per_sha_enabled?
      # for multiple check suite apps (like actions), we should return an error on conflict instead of implicit rescue
      # since this runs in a transaction (along with WorkflowRun and Workflow), other resource could conflict on create
      begin
        record.save!
      rescue ActiveRecord::RecordNotUnique => e
        GitHub.logger.error("Failed to save check suite", {
          :exception => e,
          "code.namespace" => "CheckSuite",
          "code.function" => __method__,
          "gh.app.id" => record.github_app_id,
        })

        record.errors.add(:base, CheckSuite::IntegratorCreateResult::CONFLICT_MESSAGE)
      end
    else
      # for non-multiple check suite apps, we want to rescue on uniqueness
      record = record.save_and_rescue_uniqueness
    end

    IntegratorCreateResult.new(record)
  end

  def self.create_and_rescue_uniqueness(attrs)
    new(attrs).save_and_rescue_uniqueness
  end

  def self.prefill_pushes(check_suites:, repository:)
    push_ids = check_suites.map(&:push_id).compact.uniq
    return if push_ids.empty?

    pushes = Repositories::Domain.new.pushes.load_pushes_for_repository(push_ids: push_ids, repository_id: repository.id)

    # iterate through the pushes and assign them to the check suites
    check_suites.each do |check_suite|
      next unless check_suite.push_id.present?

      check_suite.prefill_push(pushes.find { |push| push.id == check_suite.push_id })
    end
  end

  # There can be a large number of check suites associated with the same SHA due to scheduled workflows, workflow_dispath events or other CI automation users have set up.
  # See https://github.com/github/c2c-actions-checks/issues/1631
  # This function returns the most recent check suite IDs and app IDs for a given SHA
  def self.most_recent_check_suites_for_sha(repository_id, head_sha, limit)

    ActiveRecord::Base.connected_to(role: :reading) do
      binds = {
        repository_id: repository_id,
        head_sha: head_sha,
        limit: Arel.sql(limit.to_s),
      }

      sql = Arel.sql <<~SQL, **binds
        SELECT id, github_app_id
        FROM check_suites FORCE INDEX (`index_check_suites_on_head_sha_and_repository_id`)
        WHERE check_suites.head_sha = :head_sha
        AND check_suites.repository_id = :repository_id
        ORDER BY id DESC LIMIT :limit
        /*CheckSuites.most_recent_check_suites_for_sha*/
      SQL

      self.find_by_sql(sql)
    end
  end

  def save_and_rescue_uniqueness
    begin
      tap(&:save)
    rescue ActiveRecord::RecordNotUnique => e
      GitHub.dogstats.increment("checks.check_suite_uniqueness_collision", tags: ["github_app:#{well_known_app_identifier}"])
      self.class.find_by(
        repository_id: repository_id,
        github_app_id: github_app_id,
        uniqueness_key: uniqueness_key
      )
    end
  end

  def event_payload
    payload = {
      event_prefix => self,
      :repository_id => repository_id,
      :primary_resource => self.attributes
    }

    ActiveRecord::Base.connected_to(role: :reading) do
      repository = T.must(self.repository)
      payload.merge!({
        organization_id: repository.organization&.id,
        business_id: repository.organization&.business&.id
      })
    end
  end

  def deliver_workflow_run_complete_notifications
    return unless completed_with_conclusion_change? && workflow_run
    # Instrument that the WorkflowRun was requested for downstream consumers.
    notify_workflow_run(workflow_run_id: T.must(workflow_run).id, creator: creator, action: :completed)
  end

  def instrument_completion
    workflow_run = self.workflow_run
    if completed_with_conclusion_change?
      instrument :complete
      workflow_run.emit_completion_audit_log(
        actor: creator,
        attempt: workflow_run.latest_workflow_run_execution&.attempt
      ) if workflow_run
    end
  end

  def measure_completion
    if completed_with_conclusion_change?
      submit_completion_metric
    end
  end

  def submit_completion_metric
    tags = ["conclusion:#{conclusion}", "github_app:#{well_known_app_identifier}"]

    if actions_app?
      if has_reruns
        tags << "rerun:true"
      else
        tags << "rerun:false"
      end
    end

    GitHub.dogstats.distribution(
      "check_suite.completed",
      (Time.now.utc.to_i - created_at.to_i) * 1000,
      tags: tags,
    )
  end

  def instrument_status_changed
    return unless status_changed?

    GlobalInstrumenter.instrument "check_suite.status_changed", {
      check_suite_id: id,
      previous_status: T.must(status_was).to_sym,
      current_status: status.to_sym,
      repository_id: repository_id,
      head_sha: head_sha,
      conclusion: conclusion,
      app: github_app,
    }
  end

  def rerunnable?
    repository = T.must(self.repository)
    return false if repository.archived?
    return false unless check_runs_rerunnable? || rerequestable?
    return false unless completed?
    if GitHub.flipper[:checks_rerunnable_non_actions_suite].enabled?(repository) || GitHub.flipper[:checks_rerunnable_non_actions_suite].enabled?(repository.owner)
      return false if expired_workflow_run? && actions_app?
    else
      return false unless actions_app?
      return false if expired_workflow_run?
    end
    true
  end

  # Params:
  # - actor: the user making the rerequest call
  # - only_failed_check_runs - rerun only runs that failed
  # - only_failed_check_suites - ensure the suite has failed before rerunning. Potentially unused.
  # - only_check_run_id - used only by Actions to rerun a single check_run. It flows through here
  #                       instead of check_run.rerequest because launch listens for the
  #                       check_suite.rerequest event, not check_run.rerequest.
  # -  enable_debug_logging - used only by Actions to enable debug logging
  def rerequest(actor:, only_failed_check_runs: false, only_failed_check_suites: false, only_check_run_id: nil, enable_debug_logging: false)
    raise NotRerequestableError unless rerequestable

    send_workflow_pull_request_notifications = action_required?

    if only_failed_check_runs && !workflow_run.present?
      raise NotRerequestableError unless check_runs_rerunnable

      latest_check_runs.each do |run|
        if run.failed?
          run.rerequest(actor: actor)
        end
      end
    else
      raise AlreadyRerunningError if (only_failed_check_suites && !completed?) || (actions_app? && !completed?)
      raise ExpiredWorkflowRunError if expired_workflow_run?
      raise MissingWorkflowRunError if missing_workflow_run?
      raise DisabledWorkflowError if disabled_workflow?
      raise NotRerequestableError if only_failed_check_suites && !failed?


      payload = event_payload.merge(actor_id: actor.id)
      actions_meta = Hash.new

      # If re-running failed jobs or selected jobs in Actions, append failed job keys and plan ID
      if is_actions_partial_rerun?(only_failed_check_runs, only_check_run_id)
        # The workflow run plan from the previous execution is needed for partial re-runs. The plan is deleted on the log
        # expiration date. If all logs are expired, assume the plan has been deleted and do not perform partial re-runs.
        raise ExpiredLogsError if expired_logs?
        job_ids = job_ids_for_partial_rerun(only_check_run_id)
        actions_meta = actions_meta.merge(
          rerun_info: {
            plan_id: external_id,
            job_ids: job_ids,
          }
        )
      end

      if enable_debug_logging
        actions_meta = actions_meta.merge(
          enable_debug_logging: true,
        )
      end

      if actions_meta.any? && actions_app?
        payload = payload.merge(actions_meta: actions_meta)
      end

      instrument :rerequest, payload

      # Don't delete the artifacts from actions-service for partial reruns, they are instead moved to the new run
      reset(skip_artifact_file_deletion: is_actions_partial_rerun?(only_failed_check_runs, only_check_run_id))
    end

    workflow_run = self.workflow_run
    if workflow_run.present?
      previous_attempt = workflow_run.latest_workflow_run_execution&.attempt
      current_attempt = previous_attempt + 1 if previous_attempt.present?
      if only_failed_check_runs
        workflow_run.emit_rerun_only_failed_audit_log(actor: actor, attempt: current_attempt)
      elsif only_check_run_id
        workflow_run.emit_rerun_single_job_audit_log(actor: actor, attempt: current_attempt, check_run_id: only_check_run_id)
      else
        workflow_run.emit_rerun_audit_log(actor: actor, attempt: current_attempt)
      end
      workflow_run.notify_pull_request_socket_subscribers(rerun: true) if send_workflow_pull_request_notifications
    end
  end

  def request(actor: nil)
    instrument :request, event_payload.merge(
      actor_id: actor&.id,
    )
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def reset(skip_artifact_file_deletion: false)
    self.skip_update_workflow_run_execution = true

    new_status = status_pending? ? :pending : :queued

    GitHub.logger.info("Resetting check suite and updating status from #{status} to #{new_status}", {
      "gh.repo.id" => repository_id,
      "gh.check_suite.id" => id,
      "gh.check_suite.status" => status,
      "gh.check_suite.started_at" => started_at,
    })

    update(status: new_status, conclusion: nil, started_at: Time.zone.now, completed_at: nil, cancelled_at: nil)

    reset_artifacts(is_partial_rerun: skip_artifact_file_deletion)
  end

  def completed?
    conclusion.present?
  end

  def failed?
    completed? && StatusCheckConfig::FAILURE_AND_INCOMPLETE_STATES.include?(conclusion)
  end

  # Calculate the rollup values for status and conclusion
  # to represent the entire suite.
  # Based on the lowest hierarchical check run status and conclusion,
  # for all checks in the suite.
  #
  # Returns nothing.
  def set_rollup_values!
    stats_tags = ["explicit_completion:#{explicit_completion}"]

    GitHub.dogstats.time("check_suite.set_rollup_values_duration", tags: stats_tags) do
      if explicit_completion
        update_after_check_run_change_for_explicit
      else
        rollup_status, rollup_conclusion = calculate_rollup_status_conclusion

        # Set the completed_at value to the current time only if the new conclusion is not nil, but the previous one was
        completed_at = calculate_completed_at(rollup_conclusion)

        update!(conclusion: rollup_conclusion, status: rollup_status, completed_at: completed_at)
      end
    end

    notify_socket_subscribers
  end

  def calculate_rollup_status_conclusion
    if GitHub.flipper[:checks_calculate_rollup_status_original_behavior].enabled?(repository)
      # Make sure all methods use the same array of values to avoid inconsistencies
      # and to be sure that they are read from the same db connection
      check_runs = CheckRun.annotate("cross-shard-query-exempted").where(id: fetch_latest_check_run_ids)

      status = calculate_rollup_status_for_suite(check_runs)
      # The Conclusion, as per documentation, should always be nil in the case that the suite is not complete
      conclusion = status == "completed" ? calculate_rollup_conclusion(check_runs) : nil
    else
      # Make sure all methods use the same array of values to avoid inconsistencies
      # and to be sure that they are read from the same db connection
      check_runs = latest_check_runs_candidate

      status = calculate_rollup_status_for_suite_candidate(check_runs)
      # The Conclusion, as per documentation, should always be nil in the case that the suite is not complete
      conclusion = status == "completed" ? calculate_rollup_conclusion_candidate(check_runs) : nil
    end

    [status, conclusion]
  end

  def calculate_rollup_status_candidate(check_runs)
    order_sql = ["CASE"]

    CheckSuite.statuses.each do |name, value|
      order_sql << case name
      when "waiting"
        "WHEN status = #{value} THEN -0.5"
      when "pending"
        "WHEN status = #{value} THEN -0.75"
      else
        "WHEN status = #{value} THEN #{value}"
      end
    end
    order_sql << "END ASC"

    lowest_run = check_runs.order(Arel.sql(order_sql.join("\n"))).first
    status = lowest_run&.status || "requested"

    status
  end

  def calculate_rollup_conclusion_candidate(check_runs)
    order_sql = ["CASE"]
    CONCLUSIONS_HIERARCHY.each_with_index do |name, index|
      order_sql << "WHEN conclusion = #{CheckRun.conclusions[name]} THEN #{index}"
    end
    order_sql << "END ASC"

    lowest_run = check_runs.where(status: :completed).order(Arel.sql(order_sql.join("\n"))).first
    lowest_run&.conclusion
  end

  def duration
    return T.must((completed_at || started_at)) - started_at if started_at.present?
    T.must(updated_at) - created_at
  end

  private def calculate_completed_at(rollup_conclusion)
    return nil if rollup_conclusion.nil?
    return Time.zone.now if conclusion.nil? # conclusion has changed from nil to not-nil

    self.completed_at
  end

  private def update_after_check_run_change_for_explicit
    # Explicitly completed check suites have their conclusion set when marked complete
    return if status == "completed"

    rollup_status = calculate_rollup_status_for_suite(check_runs)
    new_check_suite_status = rollup_status

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => "update_after_check_run_change_for_explicit",
      "gh.check_suite.conclusion" => conclusion,
      "gh.check_suite.rollup_status" => rollup_status,
      "gh.check_suite.previous_status" => status,
      "gh.check_suite.id" => id,
      "gh.check_suite.started_at" => started_at
    ) do
      if rollup_status == "completed"
        # We must not mark check suites with explicit_completion as completed
        # except after a call to set_complete_explicitly!. So even though all check runs
        # have completed, we keep the status to in_progress / requested
        has_check_runs = check_runs.where(repository_id: repository_id).any?
        new_check_suite_status = has_check_runs ? "in_progress" : "requested"
      end

      if status == new_check_suite_status
        GitHub.logger.info("Check suite status is already '#{status}', skipping update")
        next
      end

      GitHub.logger.info("updating check suite status from #{status} to #{new_check_suite_status}", {
        "gh.check_suite.new_status" => new_check_suite_status,
      })

      current_time = ActiveRecord.default_timezone == :utc ? Time.now.utc : Time.now
      # Only update the check suite if it is not in a completed status already
      rows_affected = CheckSuite.where(id: id, repository_id: repository_id).where.not(status: "completed").update_all(status: new_check_suite_status, updated_at: current_time)

      if rows_affected > 0
        assign_attributes(status: new_check_suite_status, updated_at: current_time)

        # Manually call callbacks since doing this in SQL won't invoke them automatically
        update_workflow_run_execution # We know the status changed so we can call it always
        notify_socket_subscribers if status == "pending" # An actions rerun, could reset this to pending
        synchronize_workflow_run
      end
    end
  end

  # Marks the check suite as complete, with a known conclusion. Used for integrations that have
  # more knowledge of the state than we do. For instance it might know a suite is going
  # to fail because of a check run that isn't yet in our DB. This avoid check suites visually
  # flapping between success and another state, and multiple notifications/emails being sent.
  def set_complete_explicitly!(conclusion, run_callbacks: true)
    return unless explicit_completion

    attributes = { conclusion: conclusion, status: "completed", completed_at: Time.zone.now }

    if run_callbacks
      update(attributes)
      notify_socket_subscribers
    else
      # Callbacks will be triggered when the check_suite is saved
      # so we only need to assign the conclusion here.
      assign_attributes(attributes)
    end
  end

  def update_when_not_completed(attributes)
    current_time = ActiveRecord.default_timezone == :utc ? Time.now.utc : Time.now
    attributes = attributes.merge(updated_at: current_time)

    # Only update the check suite if it is not in a completed status already
    rows_affected = CheckSuite.where(id: id, repository_id: repository_id).where.not(status: "completed").update_all(attributes)

    if rows_affected > 0
      # Manually assign attributes so they can be used in callbacks
      assign_attributes(attributes)

      # Manually call callbacks since doing this in SQL won't invoke them automatically

      # Substitute for #instrument_status_changed
      if attributes.has_key?(:status)
        GlobalInstrumenter.instrument "check_suite.status_changed", {
          check_suite_id: id,
          previous_status: T.must(status_was).to_sym,
          current_status: status.to_sym,
          repository_id: repository_id,
          head_sha: head_sha,
          conclusion: conclusion,
          app: github_app,
        }
      end

      if completed? && attributes.has_key?(:conclusion)
        # Substitute for #instrument_completion
        instrument :complete

        workflow_run = self.workflow_run
        if workflow_run
          workflow_run.emit_completion_audit_log(
            actor: creator,
            attempt: workflow_run.latest_workflow_run_execution&.attempt
          )

          # Substitute for #deliver_workflow_run_complete_notifications
          notify_workflow_run(workflow_run_id: workflow_run.id, creator: creator, action: :completed)

          # Substitute for #deliver_notifications
          if notification_recipients.any? && !merging_upstream_into_fork?
            GitHub.newsies.trigger(
              CheckSuiteEventNotification.new(self),
              recipient_ids: notification_recipients.map(&:id),
              reason: :ci_activity,
              event_time: updated_at || created_at,
            )
            GlobalInstrumenter.instrument("check_suite.notification_triggered", { check_suite: self, conclusion: conclusion })
          end

          # Substitute for #copy_non_actions_check_runs_from_previous_execution
          copy_non_actions_check_runs_from_previous_execution_without_conclusion_check

          # Substitute for #measure_completion
          submit_completion_metric
        end
      end

      synchronize_workflow_run
      update_workflow_run_execution if attributes.has_key?(:status) # We know the status changed so we can call it always
      notify_socket_subscribers
    end
  end

  private def calculate_rollup_status_for_suite(check_runs)
    return "pending" if status_pending?
    # use helper method from ChecksRollupHelper to calculate the rollup status if not pending
    calculate_rollup_status(check_runs.where(repository_id: repository_id))
  end

  private def calculate_rollup_status_for_suite_candidate(check_runs)
    return "pending" if status_pending?
    # use helper method from ChecksRollupHelper to calculate the rollup status if not pending
    calculate_rollup_status_candidate(check_runs)
  end

  # Determins if the checksuite should be marked as "pending"
  # This should happen if we have no check_runs and there is a concurrency present on the workflow run
  private def status_pending?
    workflow_run = self.workflow_run
    !check_runs.where(repository_id: repository_id).any? && workflow_run.present? && workflow_run.concurrency.present?
  end

  # Returns the latest check runs for each name.
  #
  # Returns an a CheckRun ActiveRecord::Relation type.
  # If given a block, will pass the unloaded relation into the block as an argument.
  def latest_check_runs
    ActiveRecord::Base.connected_to(role: :reading) do
      latest_check_run_ids = fetch_latest_check_run_ids
      check_runs = latest_check_run_ids.empty? ? CheckRun.none : CheckRun.annotate("cross-shard-query-exempted").where(id: latest_check_run_ids)
      check_runs = yield(check_runs) if block_given?
      check_runs.load
    end
  end

  def latest_check_runs_count
    ActiveRecord::Base.connected_to(role: :reading) do
      fetch_latest_check_run_ids.uniq.size
    end
  end

  MATCHING_PULL_REQUESTS_REPO_ID_COUNT_LIMIT = 5000
  def matching_pull_requests(viewer = nil)
    if GitHub.flipper[:check_suite_open_pull_requests_scope].enabled?
      matching_pull_requests_candidate(viewer)
    else
      matching_pull_requests_control(viewer)
    end
  end

  # Public: Finds open pull requests matching the check suite. A pull request
  # matches a check suite if they have the same head_sha or head_branch. When
  # the check suite's head_branch is in a forked repository, it will be nil and
  # this method will return an empty ActiveRecord relation.
  #
  # Returns an ActiveRecord Relation of PullRequests.
  def matching_pull_requests_control(viewer = nil)
    return PullRequest.none unless head_branch
    return PullRequest.none unless commit
    return PullRequest.none if head_repository_id.present? && repository_id != head_repository_id

    ActiveRecord::Base.connected_to(role: :reading) do
      scope = open_pull_requests.filter_spam_for(viewer)
      repo_ids = open_pull_requests(limit: nil).filter_spam_for(viewer).pluck(:repository_id, :id).map(&:first) # vitess needs id for ordering

      # For most repos we can do this filtering with a single query, but to
      # handle the very rare outliers we operate in batches. The `break` is
      # a safety value which means that in extreme cases we may not actually
      # return _all_ the matching pull requests, but we have to impose a cap in
      # order to be sure that the returned scope is guaranteed "safe" to use.
      filtered_repo_ids = []
      repo_ids.each_slice(MATCHING_PULL_REQUESTS_REPO_ID_COUNT_LIMIT) do |ids|
        if filtered_repo_ids.length < MATCHING_PULL_REQUESTS_REPO_ID_COUNT_LIMIT
          filtered_repo_ids.concat(Repository.active.where(id: ids, user_hidden: false).pluck(:id))
        else
          break
        end
      end

      scope.where(repository_id: filtered_repo_ids).limit(100).tap do |scope|
        GitHub::PrefillAssociations.prefill_associations(scope, %i(repository base_repository head_repository))
      end
    end
  end

  # Public: Finds open pull requests matching the check suite. A pull request
  # matches a check suite if they have the same head_sha or head_branch. When
  # the check suite's head_branch is in a forked repository, it will be nil and
  # this method will return an empty ActiveRecord relation.
  #
  # Returns an ActiveRecord Relation of PullRequests.
  def matching_pull_requests_candidate(viewer = nil)
    return PullRequest.none unless head_branch
    return PullRequest.none unless commit
    return PullRequest.none if head_repository_id.present? && repository_id != head_repository_id

    ActiveRecord::Base.connected_to(role: :reading) do
      repo_ids = open_pull_requests_candidate(limit: nil).filter_spam_for(viewer).pluck(:repository_id, :id).map(&:first) # vitess needs id for ordering

      # For most repos we can do this filtering with a single query, but to
      # handle the very rare outliers we operate in batches. The `break` is
      # a safety value which means that in extreme cases we may not actually
      # return _all_ the matching pull requests, but we have to impose a cap in
      # order to be sure that the returned scope is guaranteed "safe" to use.
      filtered_repo_ids = []
      repo_ids.each_slice(MATCHING_PULL_REQUESTS_REPO_ID_COUNT_LIMIT) do |ids|
        if filtered_repo_ids.length < MATCHING_PULL_REQUESTS_REPO_ID_COUNT_LIMIT
          filtered_repo_ids.concat(Repository.active.where(id: ids, user_hidden: false).pluck(:id))
        else
          break
        end
      end

      open_pull_requests_candidate.filter_spam_for(viewer).where(repository_id: filtered_repo_ids).limit(100).tap do |scope|
        GitHub::PrefillAssociations.prefill_associations(scope, %i(repository base_repository head_repository))
      end
    end
  end

  def commit
    return @commit if defined? @commit
    # This code can be triggered by a repository deletion where associtated objects are deleted in the background.
    # It is possible that the repository is deleted before this code is executed so we need to check for it.
    return nil unless repository

    repository = T.must(self.repository)
    if repository.commits.exist?(head_sha)
      @commit = repository.commits.find(head_sha)
    else
      @commit = nil
    end
  end

  def short_head_sha
    head_sha.first(Commit::ABBREVIATED_OID_LENGTH)
  end

  def channel
    GitHub::WebSocket::Channels.check_suite(self)
  end

  def async_readable_by?(actor)
    async_repository.then do |repository|
      T.must(repository).async_readable_by?(actor)
    end
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def permalink(include_host: true, pull_request_number: nil)
    return T.must(workflow_run).permalink(include_host: include_host, pull_request_number: pull_request_number) if workflow_run
    "#{T.must(repository).permalink(include_host: include_host)}/commit/#{head_sha}/checks?check_suite_id=#{id}"
  end

  def humanized_status
    status.humanize.downcase
  end

  def log_object
    {
      "gh.check_suite.id" => id,
      "gh.check_suite.status" => status,
      "gh.check_suite.conclusion" => conclusion,
      "gh.check_suite.created_at" => created_at,
      "gh.check_suite.updated_at" => updated_at,
    }
  end

  def cancelable?
    !completed? && workflow_run? && workflow_file_path?
  end

  def cancel(actor:, force: false)
    workflow_run = T.must(self.workflow_run)
    result = if workflow_run.latest_workflow_run_execution.run_stamp_url.present?
      cancel_via_run_service(actor, force)
    else
      cancel_via_launch(actor, force)
    end

    if result.call_succeeded?
      update(cancelled_at: Time.zone.now)
      workflow_run.emit_cancel_audit_log(actor: actor) if workflow_run
    end

    result
  end

  def cancel_via_launch(actor, force)
    if github_app.launch_lab_github_app?
      Launch::Twirp.deployer_lab_client.cancel_workflow(check_suite: self, actor:, force:)
    else
      Launch::Twirp.deployer_client.cancel_workflow(check_suite: self, actor:, force:)
    end
  end

  def cancel_via_run_service(actor, force)
    workflow_run = T.must(self.workflow_run)
    run_stamp_url = workflow_run.latest_workflow_run_execution.run_stamp_url

    cancel_args = {
      plan_id: workflow_run.latest_workflow_run_execution.external_id,
      is_force_cancel: force
    }

    if actor.present?
      cancel_args[:cancelled_by] = actor.login
    end

    twirp_client = if ActionsRunService.is_lab_url?(run_stamp_url)
      ActionsRunService::Twirp::RunServiceLabClient.new(base_url: run_stamp_url)
    else
      ActionsRunService::Twirp::RunServiceClient.new(base_url: run_stamp_url)
    end

    twirp_client.cancel_plan(**cancel_args)
  end

  def head_repository_and_branch_name
    head_repository = self.head_repository
    owner = head_repository&.owner
    return head_branch unless owner.present? && head_repository_id != repository_id
    "#{owner.display_login}:#{head_branch}"
  end

  def creator
    super || User.ghost
  end

  def github_app
    super || Integration.ghost
  end

  def user_visible?(runs: nil)
    runs ||= check_runs.where(repository_id: repository_id)
    runs.any? || explicit_completion || actions_app? # actions app used to make check suites without explicit completion
  end

  def create_workflow_run
    return unless actions_app?

    # Some users use the GITHUB_TOKEN we provide in workflows to create check suites.
    # These check suites appear as created by the launch app, but we don't want to create
    # a workflow run for them. So we check if the check suite has a workflow file path.
    # This field is internal, so cannot be set when the check suite is created by a user.
    return unless workflow_file_path.present?

    self.workflow_run_data ||= Actions::WorkflowRunData.new
    workflow_name_hint = workflow_run_data.workflow_name_hint

    if event == "dynamic" && workflow_name_hint.present?
      resolved_workflow_name = workflow_name_hint
    else
      resolved_workflow_name = name
    end

    required_workflow_file_checkout_sha = nil
    unless workflow_run_data.workflow_file_checkout_sha.nil? || workflow_run_data.workflow_file_checkout_sha.empty?
      required_workflow_file_checkout_sha = workflow_run_data.workflow_file_checkout_sha
    end

    required_workflow_file_ref = nil
    if workflow_run_data.workflow_file_ref.present?
      required_workflow_file_ref = workflow_run_data.workflow_file_ref
    end

    processed_workflow_file_path, imposer_repository_id = verify_and_return_workflow_path_metadata(workflow_file_path)

    workflow = Actions::Workflow.create_or_update_workflow(processed_workflow_file_path, resolved_workflow_name, repository, nil, event, imposer_repository_id: imposer_repository_id)

    self.workflow_run = Actions::WorkflowRun.create(check_suite: self,
      workflow: workflow,
      trigger_type: workflow_run_data.trigger&.class,
      trigger_id: workflow_run_data.trigger&.id,
      execution_graph: workflow_run_data.workflow_execution_graph,
      concurrency: workflow_run_data.concurrency,
      action: workflow_run_data.action,
      actor: creator || pusher,
      workflow_run_execution_data: workflow_run_data.workflow_run_execution_data,
      workflow_file_checkout_sha: required_workflow_file_checkout_sha,
      workflow_file_ref: required_workflow_file_ref,
      tree_id: workflow_run_data.tree_id,
      cloned_workflow_run_id: workflow_run_data.cloned_workflow_run_id,
      imposer_repository_id: imposer_repository_id.nil? ? 0 : imposer_repository_id.to_i,

      # denormalized fields in both models
      name: name,
      event: event,
      repository: repository,
      head_branch: head_branch,
      head_sha: head_sha,
      workflow_file_path: processed_workflow_file_path,
    )
    T.must(workflow_run).emit_creation_audit_log(actor: creator)
  end

  def instrument_workflow_run_create
    return unless actions_app?
    return unless workflow_file_path.present?
    notify_workflow_run(workflow_run_id: T.must(workflow_run).id, creator: creator, action: :requested)
  end

  def delete_logs_from_file_storage(raise_on_error: false)
    return if skip_delete_resources_from_launch

    repository_global_relay_id = Repository::ActionsDependency.global_relay_id(repository_id)

    result = Launch::Twirp::artifacts_exchange_client_for_check_suite(self).delete_build_logs(
      repository_global_id: repository_global_relay_id,
      execution_id: external_id,
    )

    if raise_on_error && !result.call_succeeded?
      raise "Could not delete the logs from file storage"
    end
  end

  # Deletes logs from check runs, then resets this.completed_log_url
  # Used by workflow_run.delete_logs to delete logs from launch
  def delete_logs(actor:)
    delete_logs_from_file_storage(raise_on_error: true)

    check_runs.where(repository_id: repository_id).each do |check_run|
      check_run.delete_logs
    end

    # This is the last thing since this is the field we use to render the button or not to delete logs.
    # So if the deletion fails in the middle, the button will still be shown
    update(completed_log_url: nil)

    GitHub.instrument "checks.delete_logs", actor: actor, repo: repository, check_suite: self
  end

  # delete_artifacts_from_actions_service will only delete artifacts from actions service, not results
  # artifact deletion in results will be processed asynchronously by WorkflowRun#emit_workflow_run_deleted event
  def delete_artifacts_from_actions_service
    return if skip_delete_resources_from_launch

    Artifact.delete_artifacts_from_actions_service(check_suite: self, raise_on_error: false) if artifacts.count > 0
  end

  def code_scanning_app?
    return @is_code_scanning_app if defined? @is_code_scanning_app

    @is_code_scanning_app = github_app_id.present? && github_app_id == Apps::Privileged::CodeScanning.id
  end

  def has_reruns
    started_at = self.started_at
    return false unless started_at
    started_at > created_at
  end

  def annotation_count(latest_check_run_ids = nil)
    latest_check_run_ids ||= fetch_latest_check_run_ids
    @annotation_count ||= {}
    @annotation_count[latest_check_run_ids] ||= CheckAnnotation.where(check_run_id: latest_check_run_ids, repository: repository).or(CheckAnnotation.where(check_suite_id: id, repository: repository)).count
  end

  def latest_check_runs_candidate
    latest_check_runs_ids_scope = check_runs.
      joins(:check_suite).
      where(repository_id: repository_id, check_suites: { head_sha: Array(head_sha) }).
      group(:name, :check_suite_id).
      select("MAX(check_runs.id)")

    # For Actions, we want to return only check runs created after the last time the overall workflow run was started
    if actions_app?
      latest_check_runs_ids_scope = latest_check_runs_ids_scope.where("check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at)")
    end

    CheckRun.where("id IN (SELECT * FROM (?) lastest_check_runs)", latest_check_runs_ids_scope)
  end

  def fetch_latest_check_run_ids(min_start_time: nil, max_start_time: nil)
    binds = {
      head_shas: Array(head_sha),
      repository_id: repository_id,
      check_suites_id: id,
      min_start_time: min_start_time || started_at || created_at,
      max_start_time: max_start_time
    }

    sql = Arel.sql <<-SQL, **binds
      SELECT MAX(check_runs.id) AS check_run_id
        FROM check_runs
          JOIN check_suites
          ON check_runs.check_suite_id = check_suites.id
        WHERE check_suites.head_sha IN (:head_shas)
          AND check_suites.repository_id = :repository_id
          AND check_suites.id = :check_suites_id
    SQL

    # For Actions, we want to return only check runs created after the last time the overall workflow run was started
    if actions_app?
      if max_start_time.present?
        sql += Arel.sql <<-SQL, **binds
            AND check_runs.created_at BETWEEN :min_start_time AND :max_start_time
        SQL
      else
        sql += Arel.sql <<-SQL
          AND check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at)
        SQL
      end
    end

    sql += Arel.sql <<-SQL
        GROUP BY check_runs.name, check_runs.check_suite_id
        /* cross-shard-query-exempted */
    SQL

    self.class.connection.select_values(sql)
  end

  def fetch_latest_waiting_check_run_ids
    latest_check_runs { |check_runs| check_runs.where(status: :waiting) }.pluck(:id)
  end

  def workflow_filename
    workflow_file_path&.end_with?(".yml", ".yaml") ? File.basename(workflow_file_path) : ""
  end

  def lab_workflow?
    workflow_file_path&.start_with?(Actions::Workflow::WORKFLOWS_LAB_PATH)
  end

  def dynamic_workflow?
    workflow_file_path&.start_with?(Actions::Workflow::DYNAMIC_BASE_PATH)
  end

  def required_workflow?
    workflow_file_path&.start_with?(Actions::Workflow::REQUIRED_WORKFLOWS_BASE_PATH) || false
  end

  def pending_approval_gate_requests_in_environments(user, environment_ids)
    gate_requests = GateRequest.
      includes(gate: :gate_approvers).
      where(check_run_id: fetch_latest_waiting_check_run_ids)

    # Using the AR Preloader directly here instead of PrefillAssociations
    # because we want to pass a custom scope. We should get rid of this once
    # we have a gate_requests.repository_id and can add a scope to the
    # association instead
    ActiveRecord::Associations::Preloader.new(
      records: gate_requests,
      associations: :check_run,
      scope: CheckRun.where(repository_id: repository_id),
    ).call
    GitHub::PrefillAssociations.prefill_associations(gate_requests, { check_run: :deployment })

    gate_requests.select do |gate_request|
      gate_request.gate&.type == "manual_approval" && environment_ids.include?(gate_request.gate&.environment_id) && gate_request.approval_status(user) == "pending"
    end
  end

  def pending_custom_gate_requests_by_environment_name(user, environment_name)
    # we do not need gate_approvers here because integration_id is on the gates table
    gate_requests = GateRequest.
      includes(gate: :environment).
      where(check_run_id: fetch_latest_waiting_check_run_ids)

    gate_requests.select do |gate_request|
      gate_request.gate&.type == "custom" && gate_request.gate&.environment&.name == environment_name && gate_request.approval_status(user) == "pending"
    end
  end

  def mark_stale!(start_time = nil)
    start_time = start_time || Time.zone.now

    return unless T.must(self.updated_at) <= (start_time - DEFAULT_STALE_THRESHOLD)

    incomplete_check_runs = self.latest_check_runs do |check_runs|
      check_runs.where.not(status: :completed)
    end

    # Temporarily only use #update_columns to ensure no webhook events are created for this case.
    # See https://github.com/github/github/pull/143314#issuecomment-626029535 for details.
    # TODO: change #update_columns to #update! after the transition/rollout.
    incomplete_check_runs.each do |incomplete_check_run|
      # There may be old records that don't pass current validations.
      # Skip validation so we can mark them stale anyway.
      incomplete_check_run.update_columns(conclusion: :stale, status: :completed, updated_at: Time.now)
    end

    self.update_columns(conclusion: :stale, status: :completed, updated_at: Time.now)
    GitHub.dogstats.increment("checks.marked_stale")
    true
  end

  def expired_logs?
    return @expired_logs if defined?(@expired_logs)
    @expired_logs = check_runs.all? { |check_run| check_run.expired_logs? }
  end

  def safe_actor
    pusher || creator
  end

  # Unique identifier for this alert used in email messages.
  def message_id
    "<#{T.must(repository).name_with_display_owner}/check-suites/#{global_relay_id}/#{updated_at.to_i}@#{GitHub.urls.host_name}>"
  end

  memoize def pusher
    push&.pusher
  end

  memoize def pusher_id
    push&.pusher_id
  end

  def push
    return @push if defined? @push
    push_id = self.push_id
    return nil unless push_id
    @push = repositories_domain.pushes.by_id_and_repo_id(repository_id: repository_id, id: push_id)
  end

  def async_push
    return Promise.resolve(@push) if defined? @push
    push_id = self.push_id
    return Promise.resolve(nil) unless push_id

    Platform::Loaders::PushByRepository.load(repository_id, push_id).then { |push| prefill_push(push) }
  end

  def push_id=(push_id)
    remove_instance_variable :@push if defined? @push
    super
  end

  # Internal used with prefill_pushes
  def prefill_push(push)
    @push = push if push&.id == self.push_id
  end

  # Default to stripping refs/heads/ and refs/tags/ prefix from head_branch, mostly used in UI
  # Use head_branch(fully_qualified: true) if you need the full qualified ref name
  def head_branch(fully_qualified: false)
    return super() if fully_qualified
    super()&.sub(%r{\Arefs/heads/|refs/tags/}, "") || super()
  end

  private

  def completed_with_conclusion_change?
    completed? && saved_change_to_attribute?(:conclusion)
  end

  def notify_socket_subscribers
    data = if new_record?
      {
        timestamp: created_at,
        wait: default_live_updates_wait,
        reason: "check_suite ##{id} created: #{status}",
        log_archive: completed_log_url.present?,
      }
    else
      {
        timestamp: updated_at,
        wait: default_live_updates_wait,
        reason: "check_suite ##{id} updated: #{status}",
        log_archive: completed_log_url.present?,
      }
    end

    GitHub::WebSocket.notify_repository_channel(repository, channel, data)
    GlobalInstrumenter.instrument("prebuild_repository_check_suite.update", {
      check_suite_id: id,
      repository_id: repository_id,
    })

  end

  # Internal: Any open pull request that have the same head_ref as
  # the check suite
  def open_pull_requests(limit: 100)
    @open_pull_requests ||= {}
    @open_pull_requests[limit] ||= T.must(repository).pull_requests_as_head.open_pulls
      .where(head_ref: Git::Ref.safe_ref_name(ref_names: head_branch))
      .order(id: :desc)
      .limit(limit)
  end

  def open_pull_requests_candidate(limit: 100)
    @open_pull_requests_candidate ||= {}
    @open_pull_requests_candidate[limit] ||= T.must(repository).pull_requests_as_head.open_pull_requests
      .where(head_ref: Git::Ref.safe_ref_name(ref_names: head_branch))
      .order(id: :desc)
      .limit(limit)
  end

  # Non-code Actions check suites need to be hidden in most places in the UI
  # to not appear in the merge box in a PR or in the status rollup in a commit
  def calculate_hidden_flag
    self.hidden = event.present? ? VISIBLE_ACTIONS_EVENTS.exclude?(event) : false
  end

  def set_started_at
    self.started_at = self.created_at
  end

  # When resetting a suite, we remove any existing Artifacts to avoid duplicates.
  def reset_artifacts(is_partial_rerun: false)
    deleted_artifacts = []
    artifacts.each do |artifact|
      # for results artifacts, they should not be deleted on partial reruns
      # https://github.com/github/c2c-actions/blob/main/docs/adrs/vnext/7822-artifact-v4-with-partial-rerun.md
      next if artifact.is_results_artifact? && is_partial_rerun

      artifact.skip_file_deletion = is_partial_rerun
      deleted_artifacts << artifact.destroy
    end
    notify_socket_subscribers if deleted_artifacts.count > 0
  end

  def synchronize_workflow_run
    workflow_run = self.workflow_run
    if workflow_run
      workflow_run.synchronize_search_index
    end
  end

  # Internal: If check suite was created by a known app, return friendly identifier for capturing telemetry
  def well_known_app_identifier
    github_app_id_value = T.unsafe(github_app_id)

    if github_app_id_value.nil? || github_app_id_value.zero?
      :unknown
    elsif actions_app?
      :actions
    else
      case github_app_id
      when 67;    :travis
      when 254;   :codecov
      when 13473; :netlify
      when 18001; :pages
      when 9426;  :azure
      when 3414;  :wip
      when 12526; :sonarcloud
      when 2740;  :renovate
      when 8329;  :now
      when 10529; :google_cloud
      when 14084; :appveyor
      when 11006; :app_center
      when 8306, 10530, 13170; :shopify
      when 31620; :commit_message_linter
      when 12131; :reviewdog
      when 1861;  :dco
      when 3598;  :hound
      when 17324; :lgtm
      when 9695;  :gcb_poc
      when 10562; :mergify
      when 10509; :github_ci
      when 22585; :trilogy
      else;       :other
      end
    end
  end

  # for apps not allowed to have multiple check suites per sha, we set the
  # uniqueness key to the head_sha so we can prevent, at the database level,
  # duplicates that can be caused by application level race conditions.
  def set_uniqueness_key
    return if github_app.multiple_check_suites_per_sha_enabled?

    self.uniqueness_key = head_sha
  end

  # Updates corresponding fields in workflow_run_execution
  def update_workflow_run_execution
    workflow_run = self.workflow_run
    return unless workflow_run && workflow_run.workflow_run_executions.any?
    return if skip_update_workflow_run_execution

    T.must(workflow_run.workflow_run_executions.order(id: :asc).last).update!(
      status: status,
      conclusion: conclusion,
      started_at: started_at,
      completed_at: completed_at,
      completed_log_url: completed_log_url,
      external_id: external_id,
    )

    if workflow_run.in_progress?
      notify_workflow_run(workflow_run_id: workflow_run.id, creator: creator, action: :in_progress)
    end
  end

  def should_notify_socket_subscribers_of_update?
    saved_change_to_attribute?(:completed_log_url) ||
      (saved_change_to_attribute?(:status) && status == "pending") || # An actions rerun, could reset this to pending
      completed_with_conclusion_change?
  end
end
