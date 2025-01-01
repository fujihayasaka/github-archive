# typed: true
# frozen_string_literal: true

class MergeQueue < ApplicationRecord::Collab

  include GitHub::Relay::GlobalIdentification
  include GitHub::Memoizer
  include ActionView::Helpers::NumberHelper
  include Instrumentation::Model

  include MergeQueues::Command::QueueDependency

  READ_ONLY_REF_PREFIX = "refs/gh/queue/".freeze
  READ_ONLY_BRANCH_SHORT_PREFIX = "gh-readonly-queue/".freeze
  READ_ONLY_BRANCH_PREFIX = "refs/heads/#{READ_ONLY_BRANCH_SHORT_PREFIX}".freeze
  REPO_NWO_STATS_ALLOWLIST = %w[
    github/github
    github/concorde
    github/concorde-mg
    github/entitlements
  ].freeze

  ALLOWED_CHECK_RUN_RETRIES_LIMITS = [0, 1, 2, 3, 4, 5].freeze
  ALLOWED_MERGE_METHODS = %w(merge rebase squash).freeze
  SETTINGS = %w(check_run_retries_limit merge_method merging_strategy max_entries_to_build check_response_timeout_minutes min_entries_to_merge max_entries_to_merge min_entries_to_merge_wait_minutes).freeze
  NEW_ENGINE_SETTINGS = %i(merge_method merging_strategy max_entries_to_build check_response_timeout_minutes min_entries_to_merge max_entries_to_merge min_entries_to_merge_wait_minutes).freeze
  MAX_QUEUE_ENTRIES = 1000

  JOBS_RESTRAINT_LOCK_KEY_PREFIX = "merge-queue"
  JOBS_RESTRAINT_LOCK_TTL = 15.minutes
  JOBS_RESTRAINT_LOCK_CONCURRENCY = 1

  # TODO: These columns can be dropped from the schema
  self.ignored_columns = %w(
    current_merge_group_id
    max_merge_group_size
    min_merge_group_size
    min_merge_group_size_wait_seconds
  )

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true, required: true, inverse_of: :merge_queues
  belongs_to :protected_branch
  has_many :entries, -> { T.unsafe(self).sorted }, class_name: :MergeQueueEntry, inverse_of: :queue
  destroy_dependents_in_background :entries
  has_one :first_entry, -> { T.unsafe(self).sorted }, class_name: :MergeQueueEntry
  has_one :locked_entry, -> { T.unsafe(self).locked.sorted.reverse_order }, class_name: :MergeQueueEntry
  has_many :entry_stats,
    class_name: :MergeQueueEntryStat,
    inverse_of: :queue
  destroy_dependents_in_background :entry_stats
  has_many :locked_refs, class_name: :MergeQueueLockedRef
  destroy_dependents_in_background :locked_refs

  after_initialize :set_defaults, if: :new_record?

  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates :branch, presence: true, uniqueness: { scope: :repository, message: "has an existing queue" }
  validates :protected_branch, uniqueness: { allow_nil: true }
  validates :check_run_retries_limit, inclusion: { in: ALLOWED_CHECK_RUN_RETRIES_LIMITS }
  validates :merge_method, inclusion: { in: ALLOWED_MERGE_METHODS }
  validates :check_response_timeout_minutes, numericality: { in: 1..360 }
  validates :max_entries_to_build, numericality: { in: 0..100 }
  validates :max_entries_to_merge, numericality: { in: 1..100 }
  validates :min_entries_to_merge, numericality: { in: 0..100 }
  validates :min_entries_to_merge_wait_minutes, numericality: { in: 0..360 }

  validate :protected_branch_belongs_to_repo
  validate :merge_method_does_not_conflict_with_linear_history

  def self.prefill_associations(entries:, repository:, users: nil)
    GitHub::PrefillAssociations.prefill_associations(entries, :repository, available_records: [repository])
    GitHub::PrefillAssociations.prefill_associations(entries, :pull_request)
    GitHub::PrefillAssociations.prefill_associations(entries, :enqueuer, available_records: users.to_a)

    prs = entries.map(&:pull_request)
    PullRequest.prefill_associations(prs, repository: repository, users: users)
    GitHub::PrefillAssociations.prefill_batch_method(prs, :base_branch_rule_evaluator)
    PullRequest.attach_statuses(repository, prs)
    entries
  end

  # returns nil or the MergeQueue
  def self.for(repository:, branch:)
    unless repository.merge_queue_enabled?
      GitHub.logger.info(
        "merge queue is not enabled for this repository",
        "code.namespace": "MergeQueue",
        "code.function": "for",
        "gh.repo.id": repository.id,
      )
      return nil
    end
    repository.merge_queue_for(branch: branch)
  end

  def self.for_locked_oid(repository:, oid:)
    where(repository:)
      .joins(:entries)
      .where(entries: { locked: true, head_sha: oid })
  end

  # Public: Returns a string suitable for use as a repo identifier in Datadog
  def self.repo_stats_key(repository:)
    repo_nwo = repository&.name_with_owner

    if REPO_NWO_STATS_ALLOWLIST.include?(repo_nwo)
      repo_nwo
    else
      "other/other"
    end
  end

  # Public: returns the commit oid of the tip of this queue's branch.
  def branch_head_oid
    return if repository.blank? || branch.blank?
    T.must(repository).ref_to_sha(branch)
  end

  def merge_mutex(timeout: 12.seconds)
    GitHub::Redis::Mutex.new(
      "merge-queue-lock:merge:#{repository_id}:#{branch}",
      timeout:,
    )
  end

  memoize def async_required_status_checks
    GitHub.logger.info(
      "MergeQueue method call",
      "code.namespace": "MergeQueue",
      "code.function": "async_required_status_checks",
      "gh.merge_queue.id": id
    )
    async_repository.then do |repo|
      BranchRuleEvaluator.new(T.must(repo), "refs/heads/#{branch}").async_required_status_checks
    end
  end

  # Public: Can this merge queue be seen by the specified viewer?
  def readable_by?(viewer)
    T.must(repository).readable_by?(viewer)
  end

  memoize def requires_deployments_before_merging?
    return false unless evaluator = branch_rule_evaluator
    evaluator.required_deployments_enabled?
  end

  def async_requires_deployments_before_merging?
    async_branch_rule_evaluator.then do |branch_rule_evaluator|
      next false if branch_rule_evaluator.nil?
      branch_rule_evaluator.required_deployments_enabled?
    end
  end

  def wait_for_branch_rename?
    return false unless repo = repository
    repo.branch_renames.started.for_old_or_new_name(branch).exists?
  end

  def entry_for(pull_request:)
    entries.where(pull_request: pull_request).first
  end

  def has_entry_for?(pull_request:)
    if association(:entries).loaded?
      entries.detect { |entry| entry.pull_request_id == pull_request.id }.present?
    else
      entries.where(pull_request: pull_request).exists?
    end
  end

  def active_deployments
    Deployment.current_production_deployments_for_merge_queue(self).order(created_at: :desc)
  end

  sig { returns(Promise[T::Boolean]) }
  def async_actor_controlled_merging?
    async_repository.then do |repo|
      next false if repo.nil?
      next true if repo.feature_enabled?(:merge_queue_deploy_then_merge)
      next false unless repo.github_owned?

      async_requires_deployments_before_merging?
    end
  end

  sig { returns(T::Boolean) }
  def actor_controlled_merging?
    async_actor_controlled_merging?.sync
  end

  # This method returns the built MergeQueueEntry. However if the entry is not valid
  # and persisted, it will not be added to the :entries array
  def enqueue!(pull_request:, enqueuer:, solo: false, jump_queue: false)
    stats_start_time = GitHub::Dogstats.monotonic_time

    existing_entries_count = entries.count
    entry = MergeQueueEntry.new(
      queue: self,
      pull_request: pull_request,
      enqueuer: enqueuer,
      author: pull_request.user,
      solo: solo,
      jump_queue: jump_queue,
      position: existing_entries_count + 1,
      state: MergeQueues::Entry::State::Queued::VALUE,
      enqueued_rule_suite_id: nil,
      enqueued_head_sha: pull_request.head_sha,
    )

    # This check is prone to race conditions if two elements were enqueued at the exact same time. This guard is more
    # to prevent abuse than a technical limit so we're not worried if they are able to create a few extra entries.
    if existing_entries_count >= MAX_QUEUE_ENTRIES
      GitHub.logger.info(
        "merge queue full",
        "code.namespace": "MergeQueue",
        "code.function": "enqueue!",
        "gh.merge_queue.id": id,
        "gh.merge_queue.pull_request.id": entry.pull_request_id
      )

      entry.errors.add(:base, "The merge queue is full. Try again after merging or removing items from the queue")
      raise ActiveRecord::RecordInvalid.new(entry)
    end

    create_suite_result = MergeQueueEntry.create_enqueued_rule_suite(queue: self, pull_request:, enqueuer:)

    case create_suite_result
    when String
      # create_enqueued_rule_suite returned error message
      entry.validate
      entry.errors.add(:pull_request, create_suite_result)
      raise ActiveRecord::RecordInvalid.new(entry)
    when RuleEngine::RuleSuite
      entry.enqueued_rule_suite = create_suite_result
    end

    begin
      entry.save!
    rescue ActiveRecord::RecordInvalid
      entry.enqueued_rule_suite&.destroy!
      raise
    end

    MergeQueues.execute!(T.must(repository), branch)

    stat = entry.stat || entry.build_stat
    stat.update!(
      queue: self,
      enqueued_at: Time.current,
      enqueued_in_position: entry.position,
    )

    notify_subscribers(pull_request: pull_request)

    GitHub.instrument("pull_request.enqueued",
      pull_request_id: pull_request.id,
      actor_id: enqueuer.id,
    )

    entry
  ensure
    GitHub.dogstats.distribution_timing_since("merge_queue.enqueue.time", stats_start_time)
    if jump_queue
      instrument_pull_request_queue_jump(pull_request: pull_request, enqueuer: enqueuer)
    end
  end

  def instrument_pull_request_queue_jump(pull_request:, enqueuer:)
    instrument :pull_request_queue_jump, { pull_request_number: pull_request.number, enqueuer: enqueuer }
  end

  def dequeue(pull_request:, dequeuer:, raise_group_locked_error: false)
    stats_start_time = GitHub::Dogstats.monotonic_time

    unless GitHub.flipper[:consider_additional_removal_reasons_for_removable].enabled?
      return false if pull_request.merged?
    end

    entry = entries.where(pull_request: pull_request).first
    return false unless entry

    MergeQueues.remove!(queue: self, entry: entry, actor: dequeuer)

    # optimistically destroy the auto_merge_request if one exists
    # intentionally not calling #disable to not create a
    # disabled auto_merge timeline event
    pull_request.auto_merge_request&.destroy
    notify_subscribers(pull_request: pull_request)
    notify_socket_subscribers
    true
  rescue MergeQueues::Errors::GroupLocked
    GitHub.logger.info(
      "group already locked",
      "code.namespace": "MergeQueue",
      "code.function": "dequeue",
      "gh.merge_queue.id": id,
      "gh.merge_queue.pull_request.id": T.must(entry).pull_request_id
    )
    raise if raise_group_locked_error
    false
  ensure
    GitHub.dogstats.distribution_timing_since("merge_queue.dequeue.time", stats_start_time)

    instrument :pull_request_dequeued, { pull_request_number: pull_request.number, dequeuer: dequeuer, reason: MergeQueueEntry::REMOVAL_REASONS[:manual] }
  end

  def force_clear(actor:, async: false)
    args = { queue: self, actor: }
    if async
      # Delayed for the queue page to load before web socket page update fires
      MergeQueueClearQueueJob.set(wait: 5.seconds).perform_later(**args)
    else
      MergeQueueClearQueueJob.perform_now(**args)
    end
  end

  def head_entry
    entries.first
  end

  def required_deployment_environments
    return [] unless evaluator = branch_rule_evaluator
    return [] unless evaluator.required_deployments_enabled?
    evaluator.required_deployment_environments
  end

  def notify_socket_subscribers
    channel = GitHub::WebSocket::Channels.merge_queue(self)
    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      gid: global_relay_id,
      queue_entries_count: number_with_delimiter(entries.size)
    }
    GitHub::WebSocket.notify_repository_channel(repository, channel, data)
  end

  def next_entry_time_to_merge_in_seconds
    time_to_merge_estimator.estimate(position: entries.count)
  end

  def time_to_merge_estimator
    @time_to_merge_estimator ||= TimeToMergeEstimator.new(queue: self)
  end

  # Public: Returns an array of the merge_commit shas for each entry, no matter what group they are in
  #
  # Returns an array of shas
  def all_merge_commit_shas
    entries.includes(:pull_request).map(&:pull_request_merge_commit_sha)
  end

  # Public: Is the named branch locked because it is in a merge queue?
  #
  # repository - The Repository that contains the branch.
  # name       - A String branch name.
  #
  # Returns a Boolean.
  def self.branch_locked_for_merge_queue?(name, repository:)
    return false unless repository.present? && name.present?
    unless repository.merge_queue_enabled?
      GitHub.logger.info(
        "merge queue is not enabled for this repository",
        "code.namespace": "MergeQueue",
        "code.function": "branch_locked_for_merge_queue",
        "gh.repo.id": repository.id,
      )
      return false
    end

    MergeQueueLockedRef.where(
      repository: repository,
      ref: name,
    ).exists?
  end

  def async_merging_entries
    async_repository.then do |repository|
      async_entries.then do |_entries|
        MergeQueues.find_next_group(repository: T.must(repository), branch:, merge_queue: self)
      end
    end
  end

  # Public: Batch load a set of current merge head OIDs for a list of queues.
  #
  # queues - A list of MergeQueue records or record ids.
  #
  # Returns a Hash of queue => Set[oid], or queue => nil if no oid present.
  def self.head_oids_for(queues:, repository: nil)
    return {} if queues.blank?
    return {} unless repository ||= queues.first&.repository

    queues_by_id = queues.index_by(&:id)

    queues.map { |queue| [queue, Set.new] }.to_h.merge(
      MergeQueueEntry
        .where(queue: queues)
        .where.not(head_sha: nil)
        .pluck(:merge_queue_id, :head_sha)
        .group_by { |queue_id, _| queues_by_id[queue_id] }
        .transform_values { |tuples| tuples.map(&:last).to_set }
    )
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then do |repo|
      path_uri = T.must(repo).path_uri.dup
      path_uri.path += "/queue/" + branch
      path_uri
    end
  end

  def uses_queue_refs?
    T.must(repository).merge_queue_uses_queue_refs?
  end

  def queue_ref_collection
    T.must(repository).extended_refs(ref_prefix)
  end

  def ref_prefix
    if uses_queue_refs?
      MergeQueue::READ_ONLY_REF_PREFIX
    else
      MergeQueue::READ_ONLY_BRANCH_PREFIX
    end
  end

  def event_prefix() :merge_queue end

  def event_context(prefix: event_prefix)
    { "#{prefix}_branch".to_sym => branch, "#{prefix}_id".to_sym => id }
      .merge(T.must(repository).event_context)
      .merge(protected_branch&.event_context || {})
  end

  def event_payload
    payload = {
      event_prefix => self,
      :repo => repository
    }

    repo = repository

    if repo && repo.in_organization?
      payload[:org] = repo.organization
    end

    payload
  end

  # TODO: add a job argument to enforce that this should only be called from background jobs.
  def delete_refs(refnames: [], actor: nil, reraise: false)
    if refnames.empty?
      refs = queue_ref_collection
    else
      refnames = refnames.uniq.reject(&:blank?)

      unless uses_queue_refs?
        expanded_refnames = refnames + refnames.map { READ_ONLY_BRANCH_SHORT_PREFIX + _1 }
        MergeQueueLockedRef.where(ref: expanded_refnames).destroy_all
      end

      qualified_refnames = refnames.map { |name| "#{ref_prefix}#{name}" }
      refs = queue_ref_collection.find_all(qualified_refnames)
    end

    updates = refs.compact.map do |ref|
      GitHub.logger.info(
        "deleting ref",
        "code.namespace": "MergeQueue",
        "code.function": "delete_refs",
        "gh.repo.id": T.must(repository).id,
        "gh.merge_queue.id": id,
        "gh.merge_queue.ref_oid": ref.target_oid,
      )
      [ref.qualified_name, ref.target_oid, GitHub::NULL_OID]
    end

    ref_author = MergeQueues.system_actor

    # `post_receive: true` is used to push the `branch_deleted` event to CIs
    T.must(repository).batch_write_refs(ref_author, updates, reflog: { via: "merge queue" }, no_custom_hooks: true, post_receive: true)
  rescue GitHub::DGit::ThreepcFailedToLock, GitHub::DGit::UnroutedError,
         GitHub::DGit::InsufficientQuorumError, Git::Ref::ComparisonMismatch, Git::Ref::UpdateFailed => err
    if reraise
      raise
    else
      Failbot.report(err)
    end
  end

  # also called from MergeQueueClearQueueJob
  def notify_subscribers(pull_request:)
    pull_request.notify_socket_subscribers
    channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
  end

  # also called from MergeQueueClearQueueJob
  def instrument_clear(actor)
    instrument_hydro_base(event: :CLEAR, actor: actor)

    instrument :queue_cleared, { actor: actor }
  end

  sig { returns(MergeQueues::IConfiguration::MergeMethod) }
  def merge_method_type
    MergeQueues::IConfiguration::MergeMethod.deserialize(merge_method)
  end

  sig { override.returns(T.nilable(BranchRuleEvaluator)) }
  def branch_rule_evaluator
    return @branch_rule_evaluator if defined?(@branch_rule_evaluator)

    if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
      GitHub::PrefillAssociations.prefill_batch_method([repository], :plan_customer_disabled?)
    end
    @branch_rule_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(T.must(repository), branch)
  end

  sig { override.returns(Promise[T.nilable(BranchRuleEvaluator)]) }
  def async_branch_rule_evaluator
    return Promise.resolve(@branch_rule_evaluator) if defined?(@branch_rule_evaluator)

    async_repository.then do |repo|
      repo&.async_plan_customer.then do
        BranchRuleEvaluator.async_for_repository_with_branch_name(T.must(repo), branch).then do |evaluator|
          @branch_rule_evaluator = evaluator
        end
      end
    end
  end

  private

  def instrument_create
    instrument_hydro_base(event: :CREATE)
  end

  def instrument_update
    instrument_hydro_base(event: :UPDATE)

    # Create `merge_queue.update_settings` audit log event with a payload includes changed settings only
    # Skip the old engine settings
    changed_settings_payload = NEW_ENGINE_SETTINGS.each_with_object({}) do |setting, payload|
      # include the setting in the payload if it has been changed
      payload[setting] = read_attribute(setting) if saved_change_to_attribute?(setting)
    end

    instrument :update_settings, changed_settings_payload unless changed_settings_payload.blank?
  end

  def instrument_destroy
    instrument_hydro_base(event: :DESTROY)
  end

  def set_defaults
    return if branch.nil?
    if branch_rule_evaluator&.required_linear_history_enabled? && merge_method == "merge"
      self.merge_method = "squash"
    end
  end

  def protected_branch_belongs_to_repo
    return unless protected_branch
    return if protected_branch&.repository_id == repository_id

    errors.add(:protected_branch, "must belong to the repository")
  end

  # used in instrument callbacks above
  def instrument_hydro_base(event:, actor: nil)
    GlobalInstrumenter.instrument("merge_queue.event",
      event: event,
      repository: repository,
      protected_branch: protected_branch,
      queue: self,
      entries: entries.all,
      actor: actor,
    )
  end

  def merge_method_does_not_conflict_with_linear_history
    return unless merge_method == "merge"

    if branch_rule_evaluator&.required_linear_history_enabled?
      errors.add(:merge_method, "cannot be 'merge' when Linear History is required")
    end
  end
end
