# typed: strict
# frozen_string_literal: true

module MergeQueues
  # The integration that Merge Queue utilizes to perform operations on behalf of users, but when it's not an explicit
  # user interaction.
  sig { returns(User) }
  def self.system_actor
    GitHub.merge_queue_bot
  end

  # Feature flag checking if the repo has access to the legacy GraphQL APIs.
  sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
  def self.private_apis_available?(repository)
    return false if repository.nil?

    if repository.feature_flag_enabled_or_raise?(:merge_queue_legacy_api_check) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      repository.github_owned? || repository.feature_flag_enabled_or_raise?(:merge_queue_deploy_then_merge) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    else
      repository.merge_queue_enabled?
    end
  end

  sig { params(repository: Repository).void }
  def self.reconcile_queues_and_rulesets!(repository)
    RulesetReconciler.new(repository).reconcile_all
  end

  sig { params(repository: Repository, old_name: String, new_name: String).void }
  def self.handle_default_branch_rename!(repository:, old_name:, new_name:)
    RulesetReconciler.new(repository).reconcile_default_branch_rename(old_name:, new_name:)
  end

  sig { params(merge_queue: MergeQueue).returns(IConfiguration) }
  def self.configuration_for(merge_queue)
    repository = T.must(merge_queue.repository)
    owner = T.must(repository.owner)

    if evaluator = merge_queue.branch_rule_evaluator
      evaluator.merge_queue_configuration(default_configuration)
    else
      default_configuration
    end
  end

  sig { returns(IConfiguration) }
  def self.default_configuration
    @default_configuration ||= T.let(Configuration::Defaults.new, T.nilable(IConfiguration))
  end

  sig { params(repository_id: Integer, branch: String).returns(LazyLoader) }
  def self.lazy_load(repository_id, branch)
    LazyLoader.new(repository_id, branch)
  end

  # Request an evaluation of the Merge Queue for a given repository/branch
  # combination as soon as possible.
  # We include a short delay so that many requests in a short period, e.g. from
  # CI reporting results, are combined into a single run.
  sig { params(repository: Repository, branch: String).void }
  def self.execute!(repository, branch)
    MergeQueueJob.set(wait: 15.seconds).perform_later(repository, branch)
  end

  # Request an eventual evaluation of the Merge Queue for a given
  # repository/branch combination after a given delay, but without blocking
  # any calls to `.execute!` that happen in the meantime.
  sig { params(repository: Repository, branch: String, after: ActiveSupport::Duration).void }
  def self.delayed_execute!(repository, branch, after: 5.minutes)
    MergeQueueDelayedJob.set(wait: after).perform_later(repository, branch)
  end

  # Request an evaluation of the Merge Queue for a given repository/branch combination.
  # Due to the potentially high volume of calls from Checks, we will throttle executions.
  sig { params(repository: Repository, head_sha: String).void }
  def self.execute_from_sha!(repository, head_sha)
    queue = T.let(
      MergeQueue.joins(:entries).where(
        repository: repository,
        merge_queue_entries: { head_sha: }
      ).first,
      T.nilable(MergeQueue)
    )

    return unless queue

    MergeQueueShaUpdateJob.enqueue_once_per_interval(
      args: [repository, queue.branch, head_sha],
      interval: 15.seconds,
      run_at_beginning_of_interval: false,
      unique_id: "merge-queue-sha-#{queue.id}-#{head_sha}",
    )
  end

  # Remove a specific entry from the queue. This will ensure that Merge Queue state is cleaned up and that relevant objects
  # such as Pull Requests are updated.
  sig { params(queue: MergeQueue, entry: MergeQueueEntry, actor: User).void }
  def self.remove!(queue:, entry:, actor:)
    repository = T.must(queue.repository)
    branch = queue.branch

    MergeQueues::Service::RemoveEntry.new(repository, branch).call(entry:, actor:)
    execute!(repository, branch)
  end

  # Clear the Merge Queue for the given Repository and branch combination. This will ensure that Merge Queue state is
  # cleaned up and that relevant objects such as Pull Requests are updated.
  sig { params(repository: Repository, branch: String, actor: User, clear_locked_entries: T::Boolean).void }
  def self.clear!(repository:, branch:, actor:, clear_locked_entries: false)
    MergeQueues::Service::Clear.new(repository, branch).call(actor, clear_locked_entries:)
    execute!(repository, branch)
  end

  sig { params(repository: Repository, branch: String, actor: User).returns(T.nilable(MergeQueueEntry)) }
  def self.lock_best_entry!(repository:, branch:, actor:)
    Service::LockBestEntry.new(repository, branch).call(actor:)
  end

  sig { params(repository: Repository, branch: String, actor: User).returns(Service::MergeLockedEntry::Result) }
  def self.merge_locked_entry!(repository:, branch:, actor:)
    Service::MergeLockedEntry.new(repository, branch).call(actor:)
  end

  sig { params(repository: Repository, branch: String, actor: User, merge_queue: T.nilable(MergeQueue)).returns(Service::Unlock::Result) }
  def self.unlock!(repository:, branch:, actor:, merge_queue: nil)
    Service::Unlock.new(repository, branch, merge_queue).call(actor:)
  end

  sig { params(repository: Repository, branch: String, merge_queue: T.nilable(MergeQueue)).returns(T::Array[MergeQueueEntry]) }
  def self.find_next_group(repository:, branch:, merge_queue: nil)
    Service::FindNextGroup.new(repository, branch, merge_queue).call
  end

  sig do
    params(
      repository: Repository,
      branch: String,
      actor: User,
      merge_queue: T.nilable(MergeQueue)
    ).returns(MergeQueues::Service::RollBackLockedGroup::Result)
  end
  def self.roll_back_locked_group!(repository:, branch:, actor:, merge_queue: nil)
    Service::RollBackLockedGroup.new(repository, branch, merge_queue).call(actor:)
  end

  # Determine if the owner of the merge queue supports fine grained permissions.
  sig { params(owner: T.any(User, Organization)).returns(T::Boolean) }
  def self.uses_fgp?(owner)
    owner.is_a?(Organization) &&
      !FeatureFlag.vexi.enabled_or_raise?(:merge_queue_fgp_opt_out, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
end
