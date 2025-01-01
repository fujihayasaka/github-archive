# typed: true
# frozen_string_literal: true

class MergeQueueEntry < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  extend T::Sig

  include MergeQueues::Group::Groupable

  # Public: Reasons a queue entry can be removed from the queue. Keep in sync with
  # valid Hydro values in lib/hydro/schemas/github/merge_queue/v1/merge_queue_entry_event_pb.rb.
  REMOVAL_REASONS = {
    merge: "merge",
    roll_back: "roll_back",
    manual: "manual",
    merge_conflict: "merge_conflict",
    ci_failure: "ci_failure",
    queue_clear: "queue_clear",
    branch_protection_failure: "branch_protection_failure"
  }.freeze

  # NOTE: These columns were originally meant to be used for paper trail purposes.
  #       Other models exist that might be better suited for that (e.g. IssueEvent, Deployment).
  #       As we learn more we can figure out how to approach it and either keep the columns or remove them.
  self.ignored_columns = %w(dequeuer_id dequeued_at deploy_started_at repository_id)

  belongs_to :queue,
    required: true,
    class_name: :MergeQueue,
    foreign_key: :merge_queue_id,
    inverse_of: :entries

  belongs_to :pull_request, required: true, inverse_of: :merge_queue_entry
  belongs_to :enqueuer, class_name: :User, required: true
  belongs_to :author, class_name: :User, required: true
  has_one :stat, class_name: :MergeQueueEntryStat, inverse_of: :entry
  has_one :repository, through: :queue, disable_joins: true

  belongs_to :enqueued_rule_suite, class_name: "RuleEngine::RuleSuite", required: false

  scope :sorted, -> { order(locked: :desc, jump_queue: :desc, enqueued_at: :asc, id: :asc) }
  scope :locked, -> { where(locked: true) }

  validates :pull_request, uniqueness: { scope: :queue, message: "is already in the queue" }
  validate :pull_request_belongs_to_repo
  validate :eligible_for_required_deployments, on: :create
  validate :pull_request_mergeable, on: :create
  validate :authorized_enqueuer, on: :create

  before_destroy :memoize_repository_before_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :create_added_to_merge_queue_issue_event, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :create_locked_ref!, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_pr_search_index, on: [:create, :destroy] # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :remove_enqueued_rule_suite, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :destroy_locked_ref # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :clear_conflicts # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :create_removed_from_merge_queue_issue_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :state, {
    waiting: MergeQueues::Entry::State::Waiting::VALUE,
    queued: MergeQueues::Entry::State::Queued::VALUE,
    awaiting_checks: MergeQueues::Entry::State::AwaitingChecks::VALUE,
    mergeable: MergeQueues::Entry::State::Mergeable::VALUE,
    unmergeable: MergeQueues::Entry::State::Unmergeable::VALUE,
  }

  sig { returns(T::Boolean) }
  def merge_conflict?
    unmergeable? &&
      dequeue_reason == MergeQueues::Entry::RemovalReason::MergeConflict.to_i
  end

  sig { returns(T::Boolean) }
  def blocked_by_merge_conflicts?
    unmergeable? &&
      dequeue_reason == MergeQueues::Entry::RemovalReason::MergeConflict.to_i
  end

  sig { returns(Promise[T::Boolean]) }
  def async_blocked_by_merge_conflicts?
    Promise.resolve(blocked_by_merge_conflicts?)
  end

  sig { returns(T::Boolean) }
  def blocked_by_required_status?
    waiting? || required_status_pending? || required_status_failing?
  end

  sig { returns(T::Boolean) }
  def required_status_failing?
    unmergeable? &&
      dequeue_reason == MergeQueues::Entry::RemovalReason::FailedChecks.to_i
  end

  sig { returns(T::Boolean) }
  def required_status_success?
    mergeable?
  end

  sig { returns(T::Boolean) }
  def required_status_pending?
    awaiting_checks?
  end

  sig { returns(T::Boolean) }
  def waiting?
    entry_state == MergeQueues::Entry::State::Waiting ||
      entry_state == MergeQueues::Entry::State::Queued
  end

  sig { returns(String) }
  def status_check_rollup_state
    if entry_state == MergeQueues::Entry::State::Unmergeable
      StatusCheckConfig::FAILURE
    elsif entry_state == MergeQueues::Entry::State::Mergeable
      StatusCheckConfig::SUCCESS
    else
      StatusCheckConfig::WAITING
    end
  end

  sig { returns(Promise[String]) }
  def async_status_check_rollup_state
    Promise.resolve(status_check_rollup_state)
  end

  def force_solo!
    return false if solo?

    update!(solo: true)
    MergeQueues.execute!(T.must(repository), T.must(queue).branch)
  end

  def jump!(actor:)
    update!(jump_queue: true)

    MergeQueues.execute!(T.must(repository), T.must(queue).branch)
  ensure
    T.must(queue).instrument_pull_request_queue_jump(pull_request: pull_request, enqueuer: actor)
  end

  def qualified_head_ref
    return unless head_ref

    "#{T.must(queue).ref_prefix}#{head_ref}"
  end


  # Public: does this user have write permissions to the repo this queue entry is part of?

  # actor - the User to check or nil
  #
  # Returns a Boolean.
  def adminable_by?(actor)
    T.must(repository).writable_by?(actor)
  end

  def async_position
    Promise.resolve(position)
  end

  def time_to_merge_in_seconds
    async_time_to_merge_in_seconds.sync
  end

  def async_time_to_merge_in_seconds
    async_queue.then do |queue|
      async_position.then do |position|
        queue.time_to_merge_estimator.estimate(position: position)
      end
    end
  end

  def self.timestamp_attributes_for_create
    super << "enqueued_at"
  end
  private_class_method :timestamp_attributes_for_create

  sig { returns(T::Array[String]) }
  def conflicting_files
    pull_request&.merge_queue_conflict&.filenames || []
  end

  def store_conflicts(conflicts)
    pull_request&.store_conflicts(conflicts, conflict_type: :merge_queue_conflict)
  end

  def event_prefix() :merge_queue_entry end

  def event_payload
    { event_prefix => self }
      .merge(queue&.event_context || {})
      .merge(T.must(pull_request).event_context)
      .merge(T.must(enqueuer).event_context(prefix: :enqueuer))
      .merge(T.must(author).event_context(prefix: :author))
  end

  def pull_request_merge_commit_sha
    T.must(pull_request).merge_commit_sha
  end

  attr_writer :dequeuer, :removal_reason, :removal_commit_oid, :skip_timeline_event_creation_on_remove

  sig { returns(MergeQueues::Entry::State::Classes) }
  def entry_state
    MergeQueues::Entry::State.deserialize(state_before_type_cast.to_i)
  end

  def async_required_status_checks
    return Promise.resolve([]) unless head_sha.present?

    Promise.all([
      async_repository,
      async_queue
    ]).then do |repo, queue|
      queue.async_branch_rule_evaluator.then do |evaluator|
        Promise.all([
          Platform::Loaders::Statuses.load(repo, head_sha),
          Platform::Loaders::CheckRuns.load(repo, head_sha),
          evaluator.async_required_status_checks,
        ]).then do |check_statuses, check_runs, branch_required_status_checks|
          if GitHub.flipper[:optimize_mq_status_checks].enabled?(repo)
            protected_branch_required_status_check_contexts = branch_required_status_checks.pluck(:context).to_set
            check_runs = check_runs.filter { |run| protected_branch_required_status_check_contexts.include?(run.visible_name) }
            check_statuses = check_statuses.filter { |s| protected_branch_required_status_check_contexts.include?(s.context) }

            combined_status = CombinedStatus.new(repo, head_sha, statuses: check_statuses, check_runs:)
            combined_status.async_prefill.then do
              evaluator.current_statuses_with_expected(combined_status.status_checks) + evaluator.required_workflow_statuses(sha: head_sha, include_optional: false)
            end
          else
            protected_branch_required_status_check_contexts = branch_required_status_checks.pluck(:context).to_set
            check_runs = check_runs.map { |run| CombinedStatus::CheckRunAdapter.new(run) }.filter { |run| protected_branch_required_status_check_contexts.include?(run.context) }
            check_statuses = check_statuses.filter { |s| protected_branch_required_status_check_contexts.include?(s.context) }
            combined_checks = check_runs + check_statuses
            evaluator.current_statuses_with_expected(combined_checks) + evaluator.required_workflow_statuses(sha: head_sha, include_optional: false)
          end
        end
      end
    end
  end

  def required_status_checks
    async_required_status_checks.sync
  end

  sig do
    params(
      repository: Repository,
      queue: MergeQueues::Command::QueueDependency,
      entries: T::Array[MergeQueueEntry],
    ).returns(Promise[T::Hash[String, T::Array[T.any(Status, CombinedStatus::CheckRunAdapter)]]])
  end
  def self.async_merge_group_required_status_checks(repository, queue, entries)
    head_shas = entries.filter(&:enqueued_rule_suite).map(&:head_sha).compact.uniq

    return Promise.resolve(Hash.new) unless head_shas.any?

    Promise.all([
      Platform::Loaders::Statuses.new(repository).fetch(head_shas),
      Platform::Loaders::CheckRuns.new(repository).fetch(head_shas),
      queue.async_branch_rule_evaluator,
    ]).then do |all_check_statuses_by_head_sha, all_check_runs_by_head_sha, evaluator|
      # Loader doesn't return [] for shas where no records are found; instead there's just no hash entry
      all_check_statuses_by_head_sha.default = all_check_runs_by_head_sha.default = [].freeze

      evaluator.async_required_status_checks.then do |branch_required_status_checks|
        protected_branch_required_status_check_contexts = branch_required_status_checks.pluck(:context).to_set

        head_shas.each_with_object(Hash.new) do |head_sha, h|
          check_runs = all_check_runs_by_head_sha[head_sha]
            .filter { |run| protected_branch_required_status_check_contexts.include?(run.visible_name) }
            .map { |run| CombinedStatus::CheckRunAdapter.new(run) }

          check_statuses = all_check_statuses_by_head_sha[head_sha]
            .filter { |s| protected_branch_required_status_check_contexts.include?(s.context) }

          h[head_sha] = check_runs + check_statuses
        end
      end
    end
  end

  sig do
    params(
      repository: Repository,
      queue: MergeQueues::Command::QueueDependency,
      entries: T::Array[MergeQueueEntry],
    ).returns(T::Hash[String, T::Array[T.any(Status, CombinedStatus::CheckRunAdapter)]])
  end
  def self.merge_group_required_status_checks(repository, queue, entries)
    MergeQueueEntry.async_merge_group_required_status_checks(repository, queue, entries).sync
  end

  # Returns a RuleSuite object which captures the policy evaluation state when PR was added to the merge queue.
  # Retruns a String error message if there's some reason it can't be enqueued.
  sig do
    params(
      pull_request: ::PullRequest,
      enqueuer: RuleEngine::Types::Actor,
    ).returns(T.any(RuleEngine::RuleSuite, String))
  end
  def self.create_enqueued_rule_suite(pull_request:, enqueuer:)
    if pull_request.base_branch_rule_evaluator.blank?
      return "does not belong to a branch with a merge queue"
    end

    merge_state = pull_request.cached_merge_state(viewer: enqueuer)

    ref_update = merge_state.ref_update_for_merge.first
    return "not in mergeable state" unless ref_update

    if merge_state.blocked_by_invalid_merge_queue_config?
      return merge_state.blocked_by_invalid_merge_queue_config_message || "invalid merge queue configuration"
    end

    policy_decision = merge_state.rules_engine_evaluation_result

    # Create a new rule_suite which filters out rule_runs for branch protection types ignored by merge queue system
    filtered_rule_runs = policy_decision.rule_runs.reject { |run| IGNORED_BRANCH_PROTECTIONS.include?(run.rule_type) }
    filtered_rule_suite = RuleEngine::RuleSuite.for_ref_update(
      ref_update:,
      rule_runs: filtered_rule_runs,
      actor: enqueuer,
      evaluation_metadata: policy_decision.evaluation_metadata || {},
    )

    enter_queue_allowed = filtered_rule_suite.rules_fulfilled?

    if enter_queue_allowed
      filtered_rule_suite.result = :entered_queue
      filtered_rule_suite.save!
      filtered_rule_suite
    else
      policy_decision.message_without_rule_types(IGNORED_BRANCH_PROTECTIONS) || "An unknown error occurred"
    end
  end

  private

  def instrument_create
    GitHub.dogstats.increment(
      "merge_queue.queue_entry_created",
       tags: ["repository:#{MergeQueue.repo_stats_key(repository: repository)}}"]
    )
    instrument(:created) # audit log
    instrument_hydro_base(event: :CREATE) # Hydro
  end

  def instrument_update
    instrument_hydro_base(event: :UPDATE)
  end

  def instrument_destroy
    normalized_removal_reason = @removal_reason.to_s.downcase # set in #dequeue

    # Audit log
    audit_log_payload = { message: normalized_removal_reason }
    audit_log_payload.merge!(@dequeuer.event_context(prefix: :actor)) if @dequeuer # set in #dequeue
    instrument(:deleted, audit_log_payload)

    # Hydro
    valid_removal_reason = MergeQueues::Entry::RemovalReason.deserialize(normalized_removal_reason.to_sym).to_hydro_enum_value
    GitHub.dogstats.increment(
      "merge_queue.queue_entry_destroyed",
      tags: ["repository:#{MergeQueue.repo_stats_key(repository: repository)}}", "reason:#{valid_removal_reason}"]
    )
    instrument_hydro_base(event: :DESTROY,
      dequeuer: @dequeuer, # set in #dequeue
      removal_reason: valid_removal_reason,
    )
  end

  # We can't use cascading-destroy to remove the enqueued_rule_suite, since a multi-cluster SQL transaction would result.
  # The rule suite can still be in entered_queue state if, for example, the PR is removed from the queue without merging.
  def remove_enqueued_rule_suite
    if enqueued_rule_suite&.result == "entered_queue"
      enqueued_rule_suite&.destroy
    end
  end

  IGNORED_BRANCH_PROTECTIONS = [
    # TODO:
    # merge_queue and required_linear_history reasons are not currently handled as errors by MergeState.
    # This may change when these two reasons are eventually handled as error states.
    "merge_queue",
    "merge_queue_locked_ref",
    "required_linear_history",
    # required deployments aren't expected on merge queue entries, just merge groups
    "required_deployments"
  ].freeze

  def create_removed_from_merge_queue_issue_event
    # If this was triggered by a PR being destroyed no point us creating timeline events
    return if T.must(pull_request).destroyed?

    return if @skip_timeline_event_creation_on_remove
    MergeQueueEntryRemovedJob.perform_later(
      queue_id: queue&.id,
      created_at: Time.current,
      pull_request_id: pull_request_id,
      actor_id: @dequeuer&.id,
      message: @removal_reason,
      before_commit_oid: @removal_commit_oid,
      subject: T.must(author)
    )
  end

  def pull_request_belongs_to_repo
    # FIXME: How the AR association is with `required: true` but we still do the nil checks?
    return if pull_request.blank?
    return if queue.blank?
    return if T.must(queue).repository_id == T.must(pull_request).repository_id

    errors.add(:pull_request, "must belong to the queue's repository")
  end

  def eligible_for_required_deployments
    return unless T.must(queue).requires_deployments_before_merging?

    unless T.must(queue).actor_controlled_merging?
      errors.add(:pull_request, "cannot be added to a merge queue that requires deployments before merging")
    end
  end

  def pull_request_mergeable
    errors.add(:pull_request, "is in draft") if T.must(pull_request).draft?
    errors.add(:pull_request, "is closed") if T.must(pull_request).closed?
    return if errors.any? # avoid status lookups later

    case T.must(pull_request).git_merges_cleanly?
    when nil
      errors.add(:pull_request, "mergeability check has not yet completed")
    when false
      errors.add(:pull_request, "has merge conflicts")
    end

    pr_status = PullRequestStatus.new(pull_request)

    if !pr_status.required_status_success? && pr_status.required_status_failing?
      errors.add(:pull_request, "has failing required statuses")
    end
  end

  def authorized_enqueuer
    unless T.must(pull_request).base_repository&.pushable_by?(enqueuer)
      errors.add(:enqueuer, "is not authorized to merge")
    end
  end

  def create_added_to_merge_queue_issue_event
    T.must(pull_request).events.create!(event: "added_to_merge_queue", actor: enqueuer, subject: author)
  end

  def create_locked_ref!
    MergeQueueLockedRef.create_for!(entry: self)
  end

  def destroy_locked_ref
    return unless locked_ref = MergeQueueLockedRef.for(entry: self)
    locked_ref.destroy
  end

  def memoize_repository_before_destroy
    @repo_before_destroy = repository
  end

  # used in instrument callbacks above
  def instrument_hydro_base(event:, dequeuer: nil, removal_reason: nil)
    repo = @repo_before_destroy || repository
    GlobalInstrumenter.instrument("merge_queue_entry.event",
      event: event,
      repository: repo,
      queue: queue,
      entry: self,
      enqueuer: enqueuer,
      dequeuer: dequeuer,
      removal_reason: removal_reason,
      required_status_checks: [],
      queue_depth: queue&.entries&.size,
    )
  end

  def synchronize_pr_search_index
    T.must(pull_request).synchronize_search_index
  end

  def notify_socket_subscribers
    return if repository&.feature_enabled?(:merge_queue_emergency_shut_off)

    channel = T.let(nil, T.nilable(String))
    channel = GitHub::WebSocket::Channels.pull_request_merge_queue_entry_state(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
  end

  def clear_conflicts
    pull_request&.merge_queue_conflict&.destroy
  end
end
