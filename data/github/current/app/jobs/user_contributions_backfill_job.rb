# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserContributionsBackfillJob < ApplicationJob
  queue_as :user_contributions_backfill

  around_perform :use_mysql1_replica

  locked_by timeout: 1.hour, key: ->(job) {
    repo_ids = job.arguments[0]
    user_id = job.arguments[1]
    [repo_ids.first, user_id].join(":")
  }

  # If the job is still running after 60 seconds, it should requeue itself with the remanining unprocessed
  # repo IDs.
  MAX_RUNTIME = 60

  # Does the job have runtime remaining or has it hit the max runtime?
  def self.runtime_remaining?(started:)
    (Time.now - started) < MAX_RUNTIME
  end

  resolve_tenant_context do |_, user_id|
    user = User.find_by(id: user_id)
    return unless user.present?
    Business.find_by(id: user.business_id)
  end

  # This job uses repo_ids to maintain its own work queue: it will attempt
  # to process the first repo in the `repo_ids` list, and then requeues the
  # remainder.
  def perform(repo_ids, user_id, opts = {})
    queue_remainder = T.let(true, T::Boolean)
    started = Time.now
    # Clone to avoid confusing hash lock key generation
    repo_ids = repo_ids.dup

    context = opts[:context] || "unknown"

    user = T.let(nil, T.nilable(User))
    business = T.let(nil, T.nilable(Business))
    ActiveRecord::Base.connected_to(role: :reading) do
      user = User.find_by(id: user_id)
      business = user&.enterprise_managed_business
    end

    # Track how many iterations we've gone through processing this list of repo IDs
    iteration = opts[:iteration]&.to_i || 1
    starting_repo_count = repo_ids.size
    GitHub.logger.info(
      "User contribution backfill starting",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "context" => context,
      "gh.user.id" => user_id,
      "gh.user.login" => user&.login, # rubocop:disable GitHub/DoNotAllowLogin - used in logging
      "gh.business.id" => business&.id,
      "gh.business.slug" => business&.slug,
      "repo_count" => starting_repo_count,
      "iteration" => iteration,
    )

    # If the user has no emails, there won't be any commit contributions we can connect to them,
    # so clear existing contributions and skip crawling the repos.
    if user&.emails&.empty?
      GitHub.dogstats.increment("user_contributions_backfill.no_emails", tags: ["context:#{context}"])
      with_write { CommitContribution.clear_user_contributions!(user) }
      repo_ids = []

      GitHub.logger.info(
        "User contribution backfill skipping for user with no emails",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "context" => context,
        "gh.user.id" => user_id,
        "skipped_repo_count" => starting_repo_count,
        "iteration" => iteration,
        "elapsed" => Time.now - started,
      )
    end

    while repo_ids.any? do
      begin
        repo_id = repo_ids.shift

        lock_key = [repo_id, user_id].join(":")
        restraint.lock!(lock_key, 1, 1.hour) do
          repo = T.let(nil, T.nilable(Repository))
          ActiveRecord::Base.connected_to(role: :reading) do
            repo = if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
              T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
            else
              Repository.find_by(id: repo_id)
            end

            # Do validations in this read connection so we can avoid a primary read later in the process
            repo&.valid?
          end

          if repo && user
            Failbot.push repo_id: repo.id
            Failbot.push user_id: user.id
            with_write do
              CommitContribution.backfill_user!(repo, user, context: context)
            end
          end
        end
      rescue GitHub::Restraint::UnableToLock
        # Ignore and move on to the next repo
      rescue Freno::Throttler::Error
        # Automatic retry will requeue this job when this error occurs, and we
        # don't want to queue both this job and the subsequent repos at the same
        # time. Just allow this to be retried and don't queue anything else.

        queue_remainder = false
        raise
      end

      # Avoid batching if this is a retry in case batching is causing throttling.
      break if executions > 1

      break unless self.class.runtime_remaining?(started: started)
    end
  ensure
    if queue_remainder && repo_ids.any?
      GitHub.logger.info(
        "User contribution backfill requeueing",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "context" => context,
        "gh.user.id" => user_id,
        "completed_repo_count" => starting_repo_count - repo_ids.size,
        "remaining_repo_count" => repo_ids.size,
        "iteration" => iteration,
        "elapsed" => Time.now - started,
      )

      UserContributionsBackfillJob.perform_later(repo_ids, user_id, context: context, iteration: iteration + 1)
    end
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
