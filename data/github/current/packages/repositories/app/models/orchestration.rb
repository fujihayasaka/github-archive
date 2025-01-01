# typed: false
# frozen_string_literal: true

module Orchestration
  extend ActiveSupport::Concern

  class HydroPublishError < StandardError; end
  class RetryStepError < StandardError;  end

  MAX_ATTEMPTS = 7
  DEFAULT_MAX_SYNCHRONOUS_ATTEMPTS = 1
  MAX_SYNCHRONOUS_ATTEMPTS_LIMIT = 3
  STALE_TIME = 60.minutes.freeze
  RETENTION_LIMIT = 30.days.freeze
  ON_END_ORCHESTRATION_NAME = "on_end_orchestration".freeze
  SWEEPER_BATCH_SIZE = 1_000.freeze

  DB_UNAVAILABLE_ERRORS = [
    ActiveRecord::QueryCanceled,
    *Resiliency::Response::UnavailableExceptions
  ]

  FARADAY_ERRORS = [
    Faraday::ConnectionFailed,
    Faraday::TimeoutError
  ]

  GITRPC_ERRORS = [
    GitHub::Gitbackups::ClientError,
    GitHub::DGit::UnroutedError,
    GitRPC::CommandFailed,
    GitRPC::VerificationFailed,
    GitRPC::Failure,
    GitRPC::NetworkError,
    GitRPC::Protocol::DGit::ResponseError,
    GitRPC::ConnectionError
  ]

  FRENO_ERRORS = [
    Freno::Error,
    Freno::Throttler::Error,
    Freno::Throttler::CircuitOpen,
    Freno::Throttler::WaitedTooLong
  ]

  # Note that any job inheriting from RepositoryHydroMessageJob also retries on these errors, so changes here will affect multiple jobs.
  RETRYABLE_ERRORS = [
    ActiveRecord::RecordNotFound, # replication lag
    Aqueduct::Worker::JobKilled, # dirty exit
    *DB_UNAVAILABLE_ERRORS,
    *FARADAY_ERRORS,
    *FRENO_ERRORS,
    *GITRPC_ERRORS,
    Kafka::DeliveryFailed,
    Redis::TimeoutError, Redis::CannotConnectError,
    GitHub::Spokes::ClientError,
    SpokesAPI::ResourceExhausted,
    GitHub::Prioritizable::Context::LockedForRebalance,
    HydroPublishError,
    Repository::FailedDefaultBranchUpdateError,
    SpokesAPI::TwirpConnectionError,
    RetryStepError
  ]

  attr_accessor :next_step
  attr_accessor :queue_orchestration_after_commit

  @@only_save_on_orchestration_end_override = false
  def self.set_only_save_on_orchestration_end(value)
    @@only_save_on_orchestration_end_override = value
  end

  class Error < StandardError
    def failed_message
      error = message.match(/.+failed: (.+)/)
      return error[1] if error
      nil
    end
  end

  class MaxAttemptsError < StandardError;  end
  class ValidationError < StandardError;  end

  included do
    belongs_to :parent, class_name: self.name, optional: true

    serialize :data, type: Hash

    before_validation :populate, on: :create

    after_commit :queue_orchestration_job # rubocop:todo GitHub/AvoidActiveRecordCallbacks

    scope :active,      -> { where(state: [:created, :started, :running, :waiting]) }
    scope :completed,   -> { where(state: [:succeeded, :failed, :abandoned]) }
    scope :stale,       -> { where(updated_at: ..STALE_TIME.ago) }

    enum :state,
    {
      created:   0, # created but not executed yet
      started:   1, # running inline but not in a job yet. Failures will NOT be retried.
      running:   2, # running in a job and retryable
      succeeded: 3, # completed successfully
      failed:    4, # failed
      skipped:   5, # when a step is already done
      waiting:   6, # waiting for child orchestration(s) to complete
      abandoned: 7, # a stale orchestration that could not be restarted
    }

  end

  class_methods do
    # run by the RepositoryOrchestrationSweeperJob
    def restart_stuck_orchestrations
      stale_orchestrations_count_by = self.stale.active.group(:type, :step_name).count
      stale_orchestrations_count_by.each do |(type, step_name), count|
        GitHub.dogstats.gauge("#{base_orchestration_name}.stale", count, tags: ["type:#{type}", "step:#{step_name}"])
      end

      scope = self.stale.active
      scope = scope.order(state: :asc, updated_at: :asc, id: :asc)
      scope = scope.limit(SWEEPER_BATCH_SIZE)

      orchestrations = scope.to_a
      orchestrations.each { |orchestration| restart_stuck_orchestration(orchestration) }

      while orchestrations.size == SWEEPER_BATCH_SIZE
        last_orchestration = orchestrations.last

        next_page = scope.where(<<~SQL, state: self.base_orchestration.states[last_orchestration.state], updated_at: last_orchestration.updated_at, id: last_orchestration.id)
          (state = :state AND updated_at = :updated_at AND id > :id)
          OR
          (state = :state AND updated_at > :updated_at)
          OR
          (state > :state)
        SQL

        orchestrations = next_page.to_a
        orchestrations.each { |orchestration| restart_stuck_orchestration(orchestration) }
      end
    end

    def restart_stuck_orchestration(orchestration)
      if orchestration.created? || orchestration.started?
        orchestration.end_orchestration(:abandoned, "Cannot retry orchestration in state #{orchestration.state}")
        step, _ = orchestration.get_step_by_name(orchestration.step_name&.to_sym)
        orchestration.report_error(StandardError.new("Stale orchestration cannot be retried"), step)
      else
        orchestration.log_info("Orchestration kick")
        GitHub.dogstats.increment("#{base_orchestration_name}.kick_start", tags: ["type:#{orchestration.type}", "step:#{orchestration.step_name}"])
        orchestration.infer_tenant do
          orchestration.job_class.perform_later(orchestration.id, orchestration.class.to_s, kicked: true)
        end
      end
    end

    # run by the RepositoryOrchestrationSweeperJob
    def purge_old_orchestrations
      # delete old completed orchestrations to keep the table size manageable
      purgable = where("updated_at < ?", Orchestration::RETENTION_LIMIT.ago)
      tags = ["type:#{self.name}"]
      GitHub.dogstats.gauge("#{base_orchestration_name}.purgeable", purgable.count, tags: tags)
      purgable.in_batches(of: 1000) do |batch|
        throttle do
          purged = batch.delete_all
          GitHub.dogstats.count("#{base_orchestration_name}.purged", purged, tags: tags)
        end
      end
    end

    # delay time before starting the asynchronous steps
    # default is 0, but can be overridden in subclasses
    def job_start_delay
      @job_start_delay || 0.seconds
    end

    def job_start_delay=(delay)
      @job_start_delay = delay
    end

    def job_start
      all_steps << OrchestrationStep.job_start
    end

    def step(name, options = {}, &block)
      if all_steps.any? { |s| s.name == name }
        raise ArgumentError, "duplicate step name: #{name}"
      end

      unless block.nil? || self.instance_methods(false).include?(name)
        self.define_method name, block
      end
      all_steps << OrchestrationStep.new_step(name, options)
    end

    def on_end_orchestration(&block)
      self.define_method(Orchestration::ON_END_ORCHESTRATION_NAME, block)
    end

    def all_steps
      @steps ||= []
    end

    # For testing only. Stops the orchestration after the given step.
    def stop_after_step=(step_name)
      @stop_after_step = step_name
    end

    def stop_after_step
      @stop_after_step
    end

    def base_orchestration_name
      self.base_orchestration.table_name.singularize
    end
  end

  def base_orchestration
    self.class.base_orchestration
  end

  def base_orchestration_name
    self.class.base_orchestration_name
  end

  def job_class
    self.base_orchestration.try(:job_class) || raise(NotImplementedError)
  end

  def finished?
    succeeded? || failed? || skipped? || abandoned?
  end

  def active?
    created? || started? || running? || waiting?
  end

  def disown_blocking_orchestrations(orchestration_id)
    self.with_write do
      base_orchestration.where(parent_id: orchestration_id, state: [:failed, :abandoned]).update_all(parent_id: nil)
    end
  end

  def is_waiting?(waiting_id)
    base_orchestration.where(id: waiting_id).where(state: :waiting).any?
  end

  def child_orchestrations(waiting_id)
    base_orchestration.where(parent_id: waiting_id)
  end

  # record starting data before the orchestration executes
  def populate
    self.state = :created
    self.attempts = 0
    self.step_name = self.class.all_steps[0].name
  end

  def queue_orchestration_job
    if queue_orchestration_after_commit
      log_info("Queuing orchestration step", { "code.function" => __method__ })
      # turn off the flag before updating the record
      self.queue_orchestration_after_commit = false
      job_class.set(wait: self.class.job_start_delay).perform_later(self.id, self.class.to_s)
    end
  end

  # Execute the orchestration
  # synchronous: if true, execute all the steps immediately and don't queue the OrchestrationJob
  # force: if true, ignore validation errors and execute anyway, if not forced returns false if there are errors
  # Returns true if the orchestration was executed, false if it was skipped
  def execute(synchronous: false, force: false)
    begin
      execute!(synchronous: synchronous, force: force)
    rescue ValidationError
      # Exit silently. We formerly returned "skipped" and did nothing, so keep that same behavior.
      # If validation checks want to throw, they can do that themselves.
      false
    else
      true
    end
  end

  def execute!(synchronous: false, force: false)
    infer_tenant do
      run_orchestration(synchronous: synchronous, force: force)
    end
  end

  # Execute the orchestration
  # synchronous: if true, execute all the steps immediately and don't queue the OrchestrationJob
  # force: if true, ignore validation errors and execute anyway, if not forced raises a ValidationError if there are errors
  def run_orchestration(synchronous: false, force: false)
    current_step = nil
    GitHub.tracer.in_span("orchestrations.#{self.class.name.underscore}", kind: :internal, attributes: get_trace_tags) do |_span|
      if created?
        if errors.any? && !force
          log_error("Orchestration validation failed", { "code.function" => __method__ })
          raise ValidationError.new("#{self.class} validation failed")
        else
          start_or_skip!

          return if self.skipped?
        end
      end

      if waiting?
        # if we get here it means we got kicked by the sweeper job and not properly restarted
        # check if it's OK to restart
        restart_waiting_orchestration(self)
        return
      end

      if (succeeded? && step_name.nil?) || (!started? && !running? && !force)
        raise Orchestration::Error.new("#{self.class} #{self.id} has completed")
      end

      data[:synchronous] = synchronous
      early_return, error_message = nil

      loop do
        current_step, index = get_step_by_name(self.step_name&.to_sym)

        if index.nil?
          invalid_step_error = create_invalid_step_error(self.step_name)
          end_orchestration(:failed, invalid_step_error.message)
          raise invalid_step_error
        end

        if skip_step?(current_step) || (running? && current_step.job_start?)
          current_step = determine_next_step(index:)
          if current_step.nil?
            self.with_write { update!(step_name: nil) }
            break
          end
          self.with_write { update!(step_name: current_step.name) }
          next
        end

        # identify the next step after this one.
        # Could be nil if this is the last step or it is skipped
        self.next_step = determine_next_step(index:)

        if current_step.job_start?
          # bail out here when there is only one async step
          # and it is skipped
          break if self.next_step.nil?

          if synchronous
            # ignore the job_start directive. keep running here, still in the :started state
            self.with_write { update!(step_name: self.next_step.name) }
            next
          else
            self.prepare_orchestration_to_enqueue
            return
          end
        end

        early_return, error_message = attempt_step(step: current_step, force: force)

        break if early_return == :skipped || early_return == :failed || early_return == :waiting
        break if self.step_name.nil?

        if current_step.name == self.class.stop_after_step
          # Test-only scenario to stop after a specific step to simulate an inflight orchestration
          # and allow the test to inspect the orchestration or introduce race conditions, etc
          log_info("Orchestration stopped", { "code.function" => __method__ })
          # Remove the stop to avoid breaking future orchestrations and causing flaky tests
          self.class.stop_after_step = nil
          return
        end
      end

      if early_return == :skipped
        end_orchestration(:skipped, error_message)
      elsif early_return == :failed
        end_orchestration(:failed, error_message)
        e = Orchestration::Error.new("#{self.class} #{self.id} #{self.step_name} failed: #{error_message}")
        Failbot.report(e)
      elsif early_return == :waiting
        # exit quietly for now, this orchestration will get restarted when the child orchestrations finish
        end_orchestration(:waiting, nil)
      else
        # The orchestration is complete.
        end_orchestration(:succeeded, nil)
      end
    end
  rescue ValidationError
    raise
  rescue Exception => e # rubocop:todo Lint/GenericRescue
    self.with_write { self.save! } if only_save_on_orchestration_end?

    report_error(e, current_step)

    if started? || created?
      end_orchestration(:failed, e.message, error_klass: e.class)
    # The job isn't going to retry so fire end callback now
    elsif !synchronous && !Orchestration::RETRYABLE_ERRORS.include?(e.class)
      fire_on_end_orchestration(error_klass: e.class)
    end

    raise
  end

  def attempt_step(step:, force:)
    # validate we haven't exceeded our max attempts for this step
    self.attempts += 1
    max_attempts = step.max_attempts || MAX_ATTEMPTS

    early_return, error_message = nil

    if attempts > 1
      GitHub.dogstats.increment("#{base_orchestration_name}.step.retry", tags: ["type:#{self.class.name}", "step:#{step.name}", "attempt:#{attempts}"])
    end

    if attempts > max_attempts && !force
      end_orchestration(:failed, "max attempts")
      raise Orchestration::MaxAttemptsError.new("#{self.class} #{self.id} #{step.name} has exceeded max attempts (#{attempts})")
    end
    self.with_write { update!(attempts: attempts) unless only_save_on_orchestration_end? }

    # set some context in case the step blows up
    log_info("Orchestration step started", "code.function" => __method__)

    GitHub.tracer.in_span("orchestrations.#{self.class.name.underscore}.#{step.name}", kind: :internal, attributes: get_trace_tags.merge({ "#{self.class.log_prefix}.orchestration.step_name" => step.name.to_s })) do |_span|
      GitHub.dogstats.distribution_time("#{base_orchestration_name}.step.time", tags: ["type:#{self.class.name}", "step:#{step.name}"]) do
        # run the step, rescuing and handling any errors
        if step.transaction?
          transaction do
            early_return, error_message = execute_step(step)
          end
        else
          early_return, error_message = execute_step(step)
        end
      end
    end

    [early_return, error_message]

  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    allowed_attempts = [step.max_attempts || DEFAULT_MAX_SYNCHRONOUS_ATTEMPTS, MAX_SYNCHRONOUS_ATTEMPTS_LIMIT].min
    raise unless started? && retryable?(e) && self.attempts < allowed_attempts

    report_error(e, step)

    wait = 2**(self.attempts - 1) * 100
    wait += rand(wait * 0.15)
    sleep(wait / 1000.0)

    retry
  end

  # execute_step contains the logic that should be transactional when running a step that has the transaction flag set
  def execute_step(current_step)
    early_return, error_message = public_send(current_step.name)

    if early_return == :skipped || early_return == :failed
      return early_return, error_message
    end

    if @blocking_orchestrations&.any?
      # disown any failed blocking orchestrations that may already exist from previous attempts
      disown_blocking_orchestrations(self.id)

      # kick off the newly created blocking orchestrations here before we update this orchestration's state
      # because if this blows up, we'll want to rerun the current step
      @blocking_orchestrations.each do |child|
        child.execute
      end
    end

    self.step_name = self.next_step&.name
    self.attempts = 0
    self.with_write { self.save! } unless only_save_on_orchestration_end? || self.next_step&.job_start?

    if @blocking_orchestrations&.any?
      # reset the blocking orchestrations and put this orchestration into the :waiting state
      @blocking_orchestrations = nil
      return [:waiting, error_message]
    end

    [early_return, error_message]
  end

  def end_orchestration(state, error_message, error_klass: nil)
    self.state = state
    self.error_message = error_message[0, 255] if error_message
    self.with_write { self.save! }

    fire_on_end_orchestration(error_klass:)

    if state == :waiting
      # Check if we should rerun immediately, our children may have already completed/skipped
      restart_waiting_orchestration(self)
    elsif parent
      # if we have a parent, check if we should restart it
      restart_waiting_orchestration(parent)
    end

    tags = ["type:#{self.class.name}", "state:#{state}"]
    tags.append("step:#{step_name}") if step_name.present?
    GitHub.dogstats.increment("#{base_orchestration_name}.completed", tags: tags)

    elapsed_ms = ((updated_at - created_at) * 1_000).round
    GitHub.dogstats.distribution("#{base_orchestration_name}.time", elapsed_ms, tags: ["type:#{self.class.name}"])
    log_info("Orchestration ended", { "code.function" => __method__ })
  end

  def fire_on_end_orchestration(error_klass: nil)
    self.respond_to?(Orchestration::ON_END_ORCHESTRATION_NAME) && public_send(Orchestration::ON_END_ORCHESTRATION_NAME, self.error_message, error_klass)
  end

  # used by orchestration steps to indicate a failure and the need to rerun a previous step
  def set_next_step(step_name)
    self.attempts = 0
    step, _ = get_step_by_name(step_name)

    raise create_invalid_step_error(step_name) if step.nil?

    self.next_step = step
  end

  def get_step_by_name(step_name)
    step_name = step_name.to_sym if step_name.is_a?(String)

    # find the index based on the step name
    index = self.class.all_steps.find_index { |s| s.name == step_name }

    if index.nil?
      return [nil, nil]
    end

    # look up the step based on the index
    step = self.class.all_steps[index]

    [step, index]
  end

  def prepare_orchestration_to_enqueue(waiting: false)
    # enable the after_commit hook to queue the orchestration job and exit
    # we don't queue the job here because we may be inside a database transaction
    # and we need to wait for the transaction to commit before the orchestration will exist
    if waiting
      # It's possible multiple child orchestrations get here at the same time
      # and attempt to restart the same parent orchestration (self).
      # We need to ensure only one of re-queues the parent orchestration.
      # Attempt to change the state, but only if it's still waiting.
      rows_updated = self.with_write { self.class.where(id: self.id, state: :waiting).update_all(state: :running) }
      return unless rows_updated == 1
    end

    self.queue_orchestration_after_commit = true
    self.step_name = self.next_step&.name if waiting
    self.attempts = 0
    self.state = :running

    self.with_write { self.save! }
  end

  def determine_next_step(index:)
    next_step = self.class.all_steps[index + 1]
    return nil if next_step.nil?
    return next_step unless next_step.skipped?

    determine_next_step(index: index + 1)
  end

  def restart_waiting_orchestration(waiting)
    # return immediately if parent is nil or is not waiting
    return if waiting.nil?
    return unless is_waiting?(waiting.id)

    children = child_orchestrations(waiting.id)
    return if children.active.any?

    unsuccessful_children = children.where.not(state: :succeeded)

    if waiting.stop_after_waiting?(unsuccessful_children)
      waiting.end_orchestration(:failed, "child orchestration #{unsuccessful_children.first.id} failed")
      return
    end

    if waiting.step_name
      # start the parent orchestration
      waiting.next_step, _ = waiting.get_step_by_name(waiting.step_name)
      waiting.prepare_orchestration_to_enqueue(waiting: true)
    else
      # mark the parent orchestration as successful if it has no steps to run
      waiting.end_orchestration(:succeeded, nil)
    end
  end

  def block_on_orchestration(child)
    @blocking_orchestrations ||= []
    self.with_write { child.update!(parent: self) }
    @blocking_orchestrations << child
    log_info("Blocking on child", { "code.function" => __method__ })
  end

  # kwargs will be forwarded to Hydro::Publisher#publish
  # see https://github.com/github/hydro-client-ruby for more details
  def publish_hydro_event(message: nil, **kwargs)
    self.class.publish_hydro_event(message:, **kwargs)
  end

  def self.publish_hydro_event(message: nil, **kwargs)
    raise NotImplementedError
  end

  def log_info(message, options = {})
    GitHub.logger.info(
      message,
      log_data(options)
    )
  end

  def log_error(message, options = {})
    GitHub.logger.error(
      message,
      log_data(options)
    )
  end

  def retryable?(exception)
    RETRYABLE_ERRORS.any? { |klass| exception.is_a?(klass) }
  end

  def report_error(e, current_step)
    log_error(e.message, {
      :exception => e,
      "code.function" => __method__
    })

    GitHub.dogstats.increment("#{base_orchestration_name}.step.error", tags: ["type:#{self.class.name}", "step:#{current_step&.name}"])
    Failbot.report(
      e,
      failbot_data
    )
  end

  def only_save_on_orchestration_end?
    @@only_save_on_orchestration_end_override || false
  end

  def get_trace_tags
    {
      "code.function" => GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown",
      "code.namespace" => self.class.name.underscore,
      "gh.request_id" => GitHub.context[:request_id] || "",
      "#{self.class.log_prefix}.orchestration.only_save_on_end" => only_save_on_orchestration_end?.to_s,
    }
  end

  def create_invalid_step_error(step)
    Orchestration::Error.new("Invalid step named '#{step}', id #{self.id}")
  end

  # Callback to enable dynamically disabling steps via feature flags or any other runtime code.
  sig { params(step: OrchestrationStep).returns(T::Boolean) }
  def skip_step?(step)
    step.skipped?
  end

  def infer_tenant_from_repo
    return yield unless GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.blank? && repository.present?

    tenant = GitHub::CurrentTenant.unscope { Business.find_by(id: repository.tenant_id) }

    GitHub::CurrentTenant.set(tenant) { yield }
  end

  def stop_after_waiting?(unsuccessful_children)
    # by default, if our child orchestration did not succeed, then we failed and should stop
    unsuccessful_children.any?
  end

  def importing?
    data[:importing]
  end

  protected

  def target_uniqueness_condition_on_start
    raise NotImplementedError
  end

  private

  def start_or_skip!
    self.with_write do
      # We can't check for overlapping orchestrations without a uniqueness condition
      if target_uniqueness_condition_on_start.nil?
        started!
        return
      end

      raise "The uniqueness condition must be filled #{target_uniqueness_condition_on_start}" unless target_uniqueness_condition_on_start.compact_blank.keys.any?

      rows_updated = self.class.where(id: self.id, state: :created)
        .where(
          "NOT EXISTS (SELECT id FROM (?) as in_progress_orchestrations)",
          self.class.where.not(id: self.id)
            .where(state: [:started, :running])
            .where(target_uniqueness_condition_on_start)
        ).update_all(state: :started)

      # there was an in progress orchestration, abandon this one
      if rows_updated.zero?
        GitHub.dogstats.increment("#{base_orchestration_name}.ovelapping.skipped", tags: ["type:#{self.class.name}"])

        skipped!
        return
      end

      # We need to manually make the changes in the model since we updated the record using raw SQL
      # and Rails won't automatically reflect this in the model.
      # Initially we used `model.reload` to fetch the fresh data from the DB.
      # It caused a lot tests to fail because it will drop on the floor any unsaved attribute or relation.
      # I.e UserAssetTest#test_for_private_authed_assets_storage_production_policy_with_private_acl_for_private_repo_L242(packages/data/test/models/user_asset_test.rb)
      # We think it is safe to manually set the state to started here given that we are only updating this column, and at this point we know it changed rows.
      started!
    end
  end
end
