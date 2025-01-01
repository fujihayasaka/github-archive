# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class RepositorySyncJob < ApplicationJob
    include GitHub::Memoizer

    class NoRepository < StandardError; end
    class CodeScanningEnabling < StandardError; end

    queue_as :security_center
    locked_by timeout: 10.minutes, key: ->(job) { job.hash_lock_key }
    retry_on_dirty_exit

    discard_on(GitHub::DGit::NotFoundError) do |_job, error|
      GitHub.dogstats.increment("security_center.update_job.abort", tags: [
        "cause:repo_not_in_disk",
        "error:#{error.class.name.underscore}"
      ])

      GitHub.logger.warn(
        "Skipping stale repo that doesn't exist on disk",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.job.error": error.class.name,
      )
    end

    ALL_FEATURES_TYPE = "all_features"

    # Defines the list of DB clusters that the job should perform wait_for_replication on
    REQUIRED_DB_CLUSTERS = T.let([
      ::ApplicationRecord::Notify,
      ::Repository,
      ::Organization,
      ::Configuration::Entry,
    ], T::Array[T.class_of(ApplicationRecord::Base)])

    # List of retryable exceptions the job will perform retry on
    RETRYABLE_EXCEPTIONS = T.let(Resiliency::Response::UnavailableExceptions + [
      NoRepository,
      CodeScanningEnabling,
      ActiveRecord::Deadlocked,
      CodeScanning::AutoCodeqlError,
      Faraday::ConnectionFailed,
      Faraday::TimeoutError,
      Freno::Error,
      GitHub::Spokes::ClientError,
      GitRPC::NetworkError,
      ::Repository::SecurityCenterDependency::UnknownSecurityFeatureStatusError
    ], T::Array[T::Class[T.anything]])

    # List of non-retryable exceptions the job will queue for DLQ
    NON_RETRYABLE_EXCEPTIONS = T.let([
      StandardError,
    ], T::Array[T::Class[T.anything]])

    # Custom retry for recoverable exceptions, NoRepository, and CodeScanningEnabling to make job more resilient during outage.
    # ActiveJob "executions" starts at 1 since original job run is considered as 1st execution
    # and will stop retry when executions >= attempts
    RETRY_EXECUTIONS = T.let([3.seconds, 18.seconds, 83.seconds, 2.hours, 4.hours], T::Array[ActiveSupport::Duration])
    RETRYABLE_EXCEPTIONS.each do |error_class|
      retry_on error_class, wait: ->(executions) { RETRY_EXECUTIONS.at(executions - 1) }, jitter: 0.15, attempts: (RETRY_EXECUTIONS.size + 1) do |job, error|
        Failbot.report(error)
        job.retry_in_dlq(error)
        GitHub.dogstats.increment("security_center.update_job.abort", tags: [
          "cause:stopped_retry",
          "error:#{error.class.name.underscore}"
        ])
      end
    end

    # Setup restraint lock to make sure:
    # - We run one job per repo+feature at the time
    # - Allows future events to be queued if previous event handling experience high delay
    # The design of wait/attempts are here to make sure:
    # - We allows future events to have a chance to run due to above case
    # - Low wait time and attempts to make sure that exccessive events can be dropped naturally
    RESTRAINT_LOCK_CONCURRENT_JOB_LIMIT = 1
    RESTRAINT_LOCK_TTL = T.let(5.minutes.to_i, Integer)
    retry_on GitHub::Restraint::UnableToLock, wait: 5.seconds, attempts: 2 do |job|
      GitHub.dogstats.increment("security_center.update_job.unable_to_lock")
      GitHub.logger.info(
        "Update job is unable to acquire restraint lock after retries",
        "code.namespace": job.class.name,
        "code.function": __method__,
        "gh.repo.id": job.arguments.dig(0, :repository_id),
        "gh.security_center.feature_type": job.arguments.dig(0, :feature_type),
        "gh.security_center.source_event": job.arguments.dig(0, :source_event),
        "gh.security_center.job.event_timestamp": job.arguments.dig(0, :event_timestamp),
      )
    end

    sig { params(owner: T.any(Organization, User)).returns(T::Boolean) }
    def is_emu_owner?(owner)
      ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(owner)
    end

    sig { params(owner: T.any(Organization, User)).returns(T::Boolean) }
    def eligible_owner?(owner)
      owner.organization? || is_emu_owner?(owner)
    end

    sig do
      params(
        repository_id: Integer,
        source_event: String,
        feature_type: String,
        event_timestamp: T.nilable(T.any(Float, Integer)),
      )
      .void
    end
    def perform(repository_id:, source_event:, feature_type: ALL_FEATURES_TYPE, event_timestamp: nil)
      tags = all_stats_tags

      GitHub::Restraint.new.lock!(restraint_lock_key, RESTRAINT_LOCK_CONCURRENT_JOB_LIMIT, RESTRAINT_LOCK_TTL) do
        GitHub.dogstats.distribution_time("security_center.update_job.dist", tags: tags) do
          # Fetch the repo
          repo = Repositories::Public.get_active_or_deleted(repository_id)

          if repo.nil?
            # Clears data if repo is considered to be deleted after retries reading from replica
            return clear_existing_data(repository_id) if is_last_retry_of?(NoRepository)

            # On repo deletion, Dependabot alerts emit an alert resolution event - triggering security center updates.
            # We will only retry via NoRepository handling if there are actually rows in Dependabot table, indicating replication lag.
            # If there are no rows, repo is being deleted and we shouldn't retry.
            return clear_existing_data(repository_id) if feature_type == "dependabot_alerts" && !RepositoryVulnerabilityAlert.where(repository_id: repository_id).any?

            # Log repo not found to research the impact from WaitForReplication
            GitHub.dogstats.increment("security_center.update_job.repo_not_found")
            GitHub.logger.info("Repo not found", "code.namespace": self.class.name, "code.function": __method__)

            # Retry to account for replication lag
            raise NoRepository
          end

          if repo.deleted?
            if source_event != "hydro.schemas.github.repositories.v1.Deleted"
              GitHub.dogstats.count("security_center.update_job.abort", 1, tags: tags + ["cause:repo_deleted", "source_event:#{source_event}"])
            end

            clear_existing_data(repository_id)
            return
          end

          # This is to make sure we do not track records for a malformed repository.
          # These repos can exist for varies of reasons (mostly due to bugs during creations)
          # and it won't be classified as `deleted` and its data can still hold legit data in the database.
          if repo.network.nil?
            GitHub.dogstats.increment("security_center.update_job.abort", tags: tags + ["cause:repo_without_network"])
            clear_existing_data(repository_id)
            return
          end

          owner = repo.owner
          if owner.nil?
            GitHub.dogstats.increment("security_center.update_job.abort", tags: tags + ["cause:no_owner"])
            clear_existing_data(repository_id)
            return
          end


          if !eligible_owner?(owner)
            GitHub.dogstats.increment("security_center.update_job.abort", tags: tags + ["cause:owner_not_eligible"])
            clear_existing_data(repository_id)
            return
          end

          has_ghas = owner.advanced_security_purchased?
          tags << "has_ghas:#{has_ghas}"

          has_emu_owner = is_emu_owner?(owner)
          tags << "has_emu_owner:#{has_emu_owner}"

          if !has_ghas || has_emu_owner
            features_to_keep = SecurityCenter::SecurityFeatures.all_visible(owner)
            clear_existing_data(repository_id, features_to_keep: features_to_keep)

            unless features_to_keep.include?(feature_type) || feature_type == ALL_FEATURES_TYPE && features_to_keep.present?
              GitHub.dogstats.increment("security_center.update_job.abort", tags: tags + ["cause:feature_unavailable"])
              return
            end
          end

          check_code_scanning_is_not_still_enabling(repo, feature_type, source_event)

          perform_update(owner, repo, feature_type, tags)
        end
      end

      instrument_repository_updated(tags)
    rescue GitHub::Restraint::UnableToLock
      raise
    rescue *RETRYABLE_EXCEPTIONS
      raise
    rescue GitHub::DGit::NotFoundError
      raise
    rescue *NON_RETRYABLE_EXCEPTIONS => e
      Failbot.report(e)
      retry_in_dlq(T.cast(e, StandardError))
      raise
    end

    sig { returns(T::Array[String]) }
    memoize def stats_tags
      tags = []
      tags << "feature_type_input:#{arguments.dig(0, :feature_type)}"
      tags << "source_event:#{source_event}"
      tags
    end

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": arguments.dig(0, :repository_id),
        "gh.security_center.feature_type": arguments.dig(0, :feature_type),
        "gh.security_center.job.event_timestamp": arguments.dig(0, :event_timestamp),
        "gh.security_center.source_event": source_event,
      })
    end

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" }).merge(logging_context)
    end

    sig { returns(String) }
    memoize def hash_lock_key
      ActiveJob::LockingJob::DEFAULT_LOCK_STRINGIFY_PROC.call({
        repository_id: arguments.dig(0, :repository_id),
        feature_type: arguments.dig(0, :feature_type),
        source_event: source_event
      })
    end

    sig { returns(String) }
    memoize def restraint_lock_key
      self.class.restraint_lock_key(
        repository_id: arguments.dig(0, :repository_id),
        feature_type: arguments.dig(0, :feature_type) || ALL_FEATURES_TYPE,
      )
    end

    sig { params(repository_id: Integer, feature_type: String).returns(String) }
    def self.restraint_lock_key(repository_id:, feature_type:)
      DEFAULT_LOCK_STRINGIFY_PROC.call({
        repository_id:,
        feature_type:,
      })
    end

    sig { params(error: T.nilable(StandardError)).void }
    def retry_in_dlq(error)
      SecurityCenter::DeadLetterJob.schedule_for_retry(
        job_class: self.class,
        arguments: self.arguments.first,
        reason: error.class.to_s
      )
    end

    private

    sig { returns(String) }
    memoize def source_event
      arguments.dig(0, :source_event)
    end

    sig { params(tags: T::Array[String]).void }
    def instrument_repository_updated(tags)
      event_timestamp = arguments.dig(0, :event_timestamp)&.to_f
      return unless event_timestamp.present?

      elapsed_time = (Time.now.to_f - event_timestamp) * 1_000
      GitHub.dogstats.distribution("security_center.repository_updated.dist", elapsed_time, tags: tags)
      GitHub.logger.info(
        "Repository updated",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_center.repository_update.elapsed_time": elapsed_time,
      )
    end

    sig { returns(T::Boolean) }
    memoize def is_reconciliation?
      SecurityCenter::OrganizationReconciliationJob.is_reconciliation_event?(source_event) ||
        SecurityCenter::OwnerReconciliationJob.is_reconciliation_event?(source_event) ||
        SecurityCenter::BusinessReconciliationJob.is_reconciliation_event?(source_event)
    end

    sig do
      params(
        owner: T.any(User, Organization),
        repo: Repository,
        feature_type: String,
        tags: T::Array[String],
      )
      .void
    end
    def perform_update(owner, repo, feature_type, tags)
      if feature_type == ALL_FEATURES_TYPE
        SecurityCenter::SecurityFeatures.visible_features(owner).each do |ft|
          GitHub.dogstats.increment("security_center.update_job.enabled", tags: tags + ["feature_type:#{ft}"])
          repo.security_center_notify(ft, source_event: source_event)
        end

        repo_config_feature_type = SecurityCenter::SecurityFeatures::REPOSITORY_CONFIGURATION
        GitHub.dogstats.increment("security_center.update_job.enabled", tags: tags + ["feature_type:#{repo_config_feature_type}"])
        repo.security_center_notify(repo_config_feature_type, source_event: source_event)
      else
        GitHub.dogstats.increment("security_center.update_job.enabled", tags: tags + ["feature_type:#{feature_type}"])
        repo.security_center_notify(feature_type, source_event: source_event)
      end
    end

    sig do
      params(
        repo_id: Integer,
        features_to_keep: T::Array[String],
      )
      .void
    end
    def clear_existing_data(repo_id, features_to_keep: [])
      tags = ["has_features_to_keep:#{features_to_keep.size > 0}"]

      with_write do
        unless features_to_keep.include?("repository_configuration")
          RepositorySecurityCenterConfig.where(repository_id: repo_id).find_each do |existing|
            GitHub.dogstats.increment("security_center.update_job.clear_org", tags: tags + ["feature_type:repository_configuration"])
            GitHub.logger.info(
              "Clear existing data for repository",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_center.feature_type": "repository_configuration",
            )

            ApplicationRecord::Domain::RepositoriesNotify.throttle { existing.destroy }
          end
        end

        # we want to make sure we're also not removing the subfeatures of our features_to_keep (e.g. push_protection)
        features_and_subfeatures_to_keep = features_to_keep.flat_map { |f| [f] + RepositorySecurityCenterStatus.subfeatures_for(f) }.map(&:to_s)
        RepositorySecurityCenterStatus.where(repository_id: repo_id).find_each do |existing|
          next if features_and_subfeatures_to_keep.include?(existing.feature_type)

          GitHub.dogstats.increment("security_center.update_job.clear_org", tags: tags + ["feature_type:#{existing.feature_type}"])
          GitHub.logger.info(
            "Clear existing data for repository",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.feature_type": existing.feature_type,
          )

          ApplicationRecord::Domain::RepositoriesNotify.throttle { existing.destroy }
        end

        SecurityCenterAlertSeverity.where(repository_id: repo_id).find_each do |existing|
          next if features_to_keep.include?(existing.feature_type)

          GitHub.dogstats.increment("security_center.update_job.clear_org_severities", tags: tags + ["feature_type:#{existing.feature_type}"])
          GitHub.logger.info(
            "Clear existing data for repository",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_center.feature_type": existing.feature_type,
          )

          ApplicationRecord::Domain::RepositoriesNotify.throttle { existing.destroy }
        end
      end
    end

    sig do
      params(
        repo: Repository,
        feature_type: String,
        source_event: String,
      )
      .void
    end
    def check_code_scanning_is_not_still_enabling(repo, feature_type, source_event)
      return unless repo.owner&.organization?
      return unless feature_type == "code_scanning"
      return unless source_event == "repo.code_scanning_status_refreshed"
      return unless CodeScanning::AutoCodeql.new(repo).enabling?

      # Turboscan has a race condition between triggering our update and updating their default setup configuration
      # Unfortunately, there doesn't appear to be a good way to fix this on their end w/o emitting two events, as we
      # need the current event for scan completion. Therefore, if they're still enabling, we retry the job.
      #
      # If it's the last run, we don't raise the error, as we want the update to happen regardless.
      raise CodeScanningEnabling unless is_last_retry_of?(CodeScanningEnabling)
    end

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def replication_state_to_persist
      custom_state = {}

      # Set custom state for writes to make SmartDatabaseSelection to wait from now
      now = Timestamp.from_time(Time.now)
      REQUIRED_DB_CLUSTERS.compact.each do |cluster|
        # Setting gtid to nil to treat all as non-GTID writes.
        # Also SmartDatabaseSelection uses WaitForReplication to perform wait
        # which only use write timestamp instead of gtid
        custom_state[cluster.cluster_name] = { gtid: nil, time: now }
      end

      custom_state
    end

    sig { params(exception: T.class_of(StandardError)).returns(T::Boolean) }
    def is_last_retry_of?(exception)
      return false unless exception.present?
      return false unless exception_executions.present?
      (exception_executions[[exception].to_s] || 0) >= RETRY_EXECUTIONS.size
    end
  end
end
