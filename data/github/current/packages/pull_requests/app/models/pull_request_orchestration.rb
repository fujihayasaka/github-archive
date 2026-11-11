# typed: true
# frozen_string_literal: true

class PullRequestOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Memoizer
  include Orchestration
  include RepositoryOrchestrationBase
  include PullRequests::IOrchestration

  STALE_TIME = 30.minutes.freeze
  RETENTION_LIMIT = 1.day.freeze

  belongs_to :pull_request
  validates :pull_request_id, presence: true

  # this overrides the `stale` scope on the Orchestration model so that we have a shorter window for marking
  # orchestrations as stale
  scope :stale, -> { where(updated_at: ..STALE_TIME.ago) }

  sig { returns(T::Hash[Symbol, T.nilable(Integer)]) }
  protected def target_uniqueness_condition_on_start
    { repository_id: self.repository_id, pull_request_id: self.pull_request_id }
  end

  sig { returns(T.class_of(PullRequestOrchestration)) }
  def self.base_orchestration
    PullRequestOrchestration
  end

  sig { returns(T.class_of(PullRequestOrchestrationJob)) }
  def self.job_class
    PullRequestOrchestrationJob
  end

  sig { returns(String) }
  def self.log_prefix
    "gh.pull_request"
  end

  sig { void }
  def self.purge_old_orchestrations
    # Handle MakeChangeGroups with custom logic if feature flag is enabled
    if FeatureFlag.vexi.enabled?(:persist_failed_make_change_group_orchestrations, default: false)
      # For MakeChangeGroups, only purge successful orchestrations (those without failure_reason)
      make_change_groups_orchestrations = PullRequests::Orchestrations::MakeChangeGroups
        .where("updated_at < ?", RETENTION_LIMIT.ago)

      purgeable_successful_ids = make_change_groups_orchestrations.select { |orch| orch.failure_reason.nil? }.map(&:id)

      if purgeable_successful_ids.any?
        purgeable_successful = where(id: purgeable_successful_ids)
        tags = ["type:#{name}"]

        GitHub.dogstats.gauge("#{base_orchestration_name}.purgeable", purgeable_successful.count, tags: tags)

        purgeable_successful.in_batches(of: 1000) do |batch|
          throttle do
            purged = batch.delete_all
            GitHub.dogstats.count("#{base_orchestration_name}.purged", purged, tags: tags)
          end
        end
      end

      other_orchestrations = where.not(type: "PullRequests::Orchestrations::MakeChangeGroups")
        .where("updated_at < ?", RETENTION_LIMIT.ago)

      if other_orchestrations.any?
        tags = ["type:#{name}"]
        GitHub.dogstats.gauge("#{base_orchestration_name}.purgeable", other_orchestrations.count, tags: tags)

        other_orchestrations.in_batches(of: 1000) do |batch|
          throttle do
            purged = batch.delete_all
            GitHub.dogstats.count("#{base_orchestration_name}.purged", purged, tags: tags)
          end
        end
      end
    else
      purgeable = where("updated_at < ?", RETENTION_LIMIT.ago)
      tags = ["type:#{name}"]
      GitHub.dogstats.gauge("#{base_orchestration_name}.purgeable", purgeable.count, tags: tags)
      purgeable.in_batches(of: 1000) do |batch|
        throttle do
          purged = batch.delete_all
          GitHub.dogstats.count("#{base_orchestration_name}.purged", purged, tags: tags)
        end
      end
    end
  end

  sig { void }
  def validate_no_duplicates
    # TODO(dzader): consider adding a unique index on repo_id,pr_id,in_progress_state to ensure we only ever have one orchestration in progress
    if self.class.active.where(type: self.class, repository_id: repository_id, pull_request_id: pull_request_id).exists?
      errors.add(:base, :duplicate, message: duplicate_orchestration_error_message)
    end
  end

  sig { params(options: Hash).returns(Hash) }
  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request.orchestration.id" => id,
      "gh.pull_request.orchestration.type" => type,
      "gh.pull_request.orchestration.state" => state,
      "gh.pull_request.orchestration.step_name" => step_name,
      "gh.pull_request.orchestration.attempts" => attempts,
      "gh.pull_request.orchestration.data" => data,
      "gh.pull_request.orchestration.error_message" => error_message,
      "gh.repo.id" => repository_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  sig { returns(Hash) }
  def failbot_data
    {
      "gh.repo.id" => repository_id,
      "gh.pull_request.id" => pull_request_id,
      "gh.pull_request.orchestration.id" => id,
      "gh.pull_request.orchestration.step_name" => step_name,
      "gh.pull_request.orchestration.type" => type
    }
  end

  sig { returns(T.nilable(User)) }
  memoize def user
    User.find_by(id: data[:user_id])
  end

  def start_or_skip!
    # this method is lifted from the base Orchestration class so that we can iterate on it and adjust the scopes
    # by which pull request orchestration records are retrieved and updated

    # fall back to the `start_or_skip!` method on the base Orchestration class if this orchestration's pull
    # request's repository is enrolled
    return super if FeatureFlag.vexi.enabled?(:pull_request_orchestrations_start_or_skip_fallback, default: false)

    GitHub.dogstats.increment("pull_request_orchestrations.start_or_skip_override", tags: ["type:#{self.class.name}"])

    self.with_write do
      # We can't check for overlapping orchestrations without a uniqueness condition
      if target_uniqueness_condition_on_start.nil?
        started!
        return
      end

      raise "The uniqueness condition must be filled #{target_uniqueness_condition_on_start}" unless target_uniqueness_condition_on_start.compact_blank.keys.any?

      if logged_disallowed_concurrent_orchestration_types.any?
        logged_concurrent_orchestrations = concurrent_orchestrations_scope(logged_disallowed_concurrent_orchestration_types).limit(5).pluck(:id, :type)
        if logged_concurrent_orchestrations.any?
          GitHub.dogstats.increment(
            "#{base_orchestration_name}.overlapping.logged",
            tags: [
              "type:#{self.class.name}",
              "concurrent_type:#{logged_concurrent_orchestrations.first.last}"]
            )

          log_info("Found other active disallowed concurrent orchestrations", {
            "#{self.class.log_prefix}.orchestration.concurrent_orchestrations" => logged_concurrent_orchestrations.to_s
          })
        end
      end

      if disallowed_concurrent_orchestration_types.any?
        rows_updated = with_read_committed(action: "update_orchestration_started") do
          self.class.where(id: self.id, state: :created)
          .where(skip_sharding_hint ? nil : target_uniqueness_condition_on_start)
          .where(
            "NOT EXISTS (SELECT id FROM (?) as in_progress_orchestrations)",
            concurrent_orchestrations_scope(disallowed_concurrent_orchestration_types)
          ).update_all(state: :started)
        end
      else
        rows_updated = with_read_committed(action: "update_orchestration_started") do
          self.class.where(id: self.id, state: :created)
            .where(target_uniqueness_condition_on_start)
            .where(
              "NOT EXISTS (SELECT id FROM (?) as in_progress_orchestrations)",
              self.class.where.not(id: self.id)
                .where(state: [:started, :running])
                .where(target_uniqueness_condition_on_start)
            ).update_all(state: :started)
        end
      end

      # there was an in progress orchestration, abandon this one
      if rows_updated.zero?
        GitHub.dogstats.increment(
          "#{base_orchestration_name}.overlapping.skipped",
          tags: [
            "type:#{self.class.name}",
            "disallowed_concurrent_orchestrations:#{disallowed_concurrent_orchestration_types.any?}"]
          )

        log_info("Disallowed concurrent orchestrations prevented orchestration from starting")

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

  def attempt_step(step:, force:)
    success = false
    enhanced_step_logging = FeatureFlag.vexi.enabled?(:pull_request_orchestration_step_duration_logging, repository, default: false)

    if enhanced_step_logging
      start_time = GitHub::Dogstats.monotonic_time
    end

    # validate we haven't exceeded our max attempts for this step
    self.attempts += 1
    max_attempts = step.max_attempts || MAX_ATTEMPTS

    early_return = T.let(nil, T.untyped)
    error_message = T.let(nil, T.untyped)

    if attempts > 1
      GitHub.dogstats.increment("#{base_orchestration_name}.step.retry", tags: ["type:#{self.class.name}", "step:#{step.name}", "attempt:#{attempts}"] + datadog_tags)
    end

    if attempts > max_attempts && !force
      end_orchestration(:failed, "max attempts")
      raise Orchestration::MaxAttemptsError.new("#{self.class} #{self.id} #{step.name} has exceeded max attempts (#{attempts})")
    end
    self.with_write { update!(attempts: attempts) unless only_save_on_orchestration_end? }

    log_tags = {
      "code.function" => __method__,
      "gh.pull_request.orchestration.step_name" => step.name.to_s,
    }

    log_tags.merge!(PullRequests::Observability::TimeBudgets.remaining_time_budget_tags) if enhanced_step_logging

    # set some context in case the step blows up
    log_info(
      "Orchestration step started",
      log_tags,
    )

    step_error = T.let(nil, T.nilable(StandardError))

    GitHub.tracer.in_span("orchestrations.#{self.class.name&.underscore}.#{step.name}", kind: :internal, attributes: get_trace_tags.merge({ "#{self.class.log_prefix}.orchestration.step_name" => step.name.to_s })) do |_span|
      GitHub.dogstats.distribution_time("#{base_orchestration_name}.step.time", tags: ["type:#{self.class.name}", "step:#{step.name}"] + datadog_tags) do
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

    success = true
    [early_return, error_message]
  rescue StandardError => e
    step_error = e
    allowed_attempts = [step.max_attempts || DEFAULT_MAX_SYNCHRONOUS_ATTEMPTS, MAX_SYNCHRONOUS_ATTEMPTS_LIMIT].min
    raise unless started? && retryable?(e) && self.attempts < allowed_attempts

    report_error(e, step)

    wait = 2**(self.attempts - 1) * 100
    wait += rand(wait * 0.15)
    sleep(wait / 1000.0)

    retry
  ensure
    if enhanced_step_logging

      if start_time
        duration = GitHub::Dogstats.duration(start_time)
      end

      log_info(
        "Orchestration step ended",
        {
          "code.function" => __method__,
          "gh.pull_request.orchestration.step_name" => step.name.to_s,
          "gh.pull_request.orchestration.step.duration" => duration || "unknown",
          "gh.pull_request.orchestration.step.error" => step_error&.class&.name,
          "gh.pull_request.orchestration.step.success" => success,
        }.merge(PullRequests::Observability::TimeBudgets.remaining_time_budget_tags),
      )
    end
  end

  private

  sig { returns(String) }
  def duplicate_orchestration_error_message
    "orchestration in progress"
  end

  def with_read_committed(action:, &block)
    ApplicationRecord::Domain::IssuesPullRequests.connection_pool.with_connection do |connection|
      connection.execute("SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED")
      begin
        connection.transaction do
          level = connection.execute("SELECT @@transaction_isolation").first
          report_isolation_level_metric(level&.first, action)

          yield
        end
      ensure
        connection.execute("SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ")
      end
    end
  end

  def report_isolation_level_metric(level_name, action_name)
    level_tag = if level_name == "READ-COMMITTED"
      "level:read_committed"
    elsif level_name == "REPEATABLE-READ"
      "level:repeatable_read"
    else
      "level:#{level_name}"
    end

    GitHub.dogstats.distribution("pull_request_orchestrations.isolation_level", 1, tags: [level_tag, "action:#{action_name}"])
  end
end
