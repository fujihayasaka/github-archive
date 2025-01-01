# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Wrapper object for the Command class that allows for logging of all side effects performed by the core Command
  # class.
  class CommandActionLogger
    extend T::Sig
    include ICommand

    class Action < T::Struct
      class Name < T::Enum
        enums do
          CreateRef = new(:create_ref!)
          DeleteRef = new(:delete_ref!)
          DispatchWebhook = new(:dispatch_webhook!)
          FinalizeRuleSuiteRecords = new(:finalize_rule_suite_records!)
          Merge = new(:merge!)
          RecalculatePositions = new(:recalculate_positions!)
          RecordMergeStats = new(:record_merge_stats!)
          RecordMergeGroupFailure = new(:record_merge_group_failure!)
          Remove = new(:remove!)
          RequestChecks = new(:request_checks!)
          RetryChecks = new(:retry_checks!)
          StoreMergeConflict = new(:store_merge_conflict!)
          Update = new(:update!)
          UpdateMergedPullRequest = new(:update_merged_pull_requests!)
        end
      end

      extend T::Sig

      const :name, Name
      const :merge_queue_entry_id, Integer
      const :pull_request_number, Integer
      const :state, T.nilable(Entry::State), default: nil
      const :removal_reason, T.nilable(Entry::RemovalReason), default: nil
      const :hook_payload, T.nilable(WebHook), default: nil

      sig do
        params(
          entry: T.any(Entry, MergeQueueEntry),
          name: Name,
          state: T.nilable(Entry::State),
          removal_reason: T.nilable(Entry::RemovalReason),
          hook_payload: T.nilable(WebHook),
        ).returns(T.attached_class)
      end
      def self.for(entry:, name:, state: nil, removal_reason: nil, hook_payload: nil)
        case entry
        when Entry
          merge_queue_entry_id = entry.merge_queue_entry_id
          pull_request_number = entry.pull_request_number
        when MergeQueueEntry
          merge_queue_entry_id = T.must(entry.id)
          pull_request_number = entry.pull_request&.number
        else
          T.absurd(entry)
        end

        new(
          merge_queue_entry_id:,
          pull_request_number:,
          name:,
          state:,
          removal_reason:,
          hook_payload:,
        )
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        if other.is_a?(Action)
          other.name == name &&
            other.merge_queue_entry_id == merge_queue_entry_id &&
            other.pull_request_number == pull_request_number &&
            other.state == state &&
            other.removal_reason == removal_reason &&
            other.hook_payload == hook_payload
        else
          false
        end
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
      def as_json(options = {})
        # Custom implementation to ensure ordered output
        # It makes the logs a lot easier to read!
        {
          "name" => name.serialize,
          "merge_queue_entry_id" => merge_queue_entry_id,
          "pull_request_number" => pull_request_number,
          "state" => state.as_json,
          "removal_reason" => removal_reason,
          "hook_payload" => hook_payload&.class&.name,
        }.compact
      end

      sig { returns(String) }
      def to_s
        string = "##{pull_request_number}: #{name.serialize}"

        if current_state = state
          string << " to #{current_state.class.name&.demodulize}"
        end

        if current_removal_reason = removal_reason
          string << " because #{current_removal_reason}"
        end

        if current_hook_payload = hook_payload
          string << " with #{hook_payload}"
        end

        string
      end
    end

    sig { returns(T::Array[Action]) }
    attr_reader :actions

    sig { params(implementation: ICommand).void }
    def initialize(implementation)
      @implementation = implementation
      @actions = T.let([], T::Array[Action])
    end

    # @see [MergeQueues::Command#merge!]
    sig do
      override.params(
        entry: T.any(Entry, MergeQueueEntry),
        expected_base_sha: String,
        actor: T.nilable(User),
      ).returns(MergeResult)
    end
    def merge!(entry, expected_base_sha:, actor: nil)
      @actions << Action.for(entry:, name: Action::Name::Merge)

      @implementation.merge!(entry, actor:, expected_base_sha:)
    end

    # @see [MergeQueues::Command#finalize_rule_suite_records!]
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def finalize_rule_suite_records!(entries, merge_method:)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::FinalizeRuleSuiteRecords)
      end)

      @implementation.finalize_rule_suite_records!(entries, merge_method:)
    end

    # @see [MergeQueues::Command#update_merged_pull_requests!]
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess,
        merge_method: IConfiguration::MergeMethod,
        merge_action: T.nilable(Symbol),
      ).returns(GenericResult)
    end
    def update_merged_pull_requests!(entries, merge_result:, merge_method:, merge_action: nil)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::UpdateMergedPullRequest)
      end)

      @implementation.update_merged_pull_requests!(entries, merge_result:, merge_method:, merge_action:)
    end

    # @see [MergeQueues::Command#record_merge_stats!]
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess
      ).returns(GenericResult)
    end
    def record_merge_stats!(entries, merge_result:)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::RecordMergeStats)
      end)

      @implementation.record_merge_stats!(entries, merge_result:)
    end

    # @see [MergeQueues::Command#record_merge_group_failure!]
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::BranchProtectionError,
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def record_merge_group_failure!(entries, merge_result:, merge_method:)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::RecordMergeGroupFailure)
      end)

      @implementation.record_merge_group_failure!(entries, merge_result:, merge_method:)
    end

    # @see [MergeQueues::Command#remove!]
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        actor: T.nilable(User),
        reason: T.nilable(Entry::RemovalReason)
      ).returns(GenericResult)
    end
    def remove!(entries, actor: nil, reason: nil)
      @actions.concat(entries.map do |entry|
        entry_reason = case entry
        when Entry
          entry.removal_reason
        when MergeQueueEntry
          nil
        else
          T.absurd(entry)
        end

        Action.for(
          entry:,
          name: Action::Name::Remove,
          removal_reason: reason || entry_reason || Entry::RemovalReason::Unknown,
        )
      end)

      @implementation.remove!(entries, actor:, reason:)
    end

    # @see [MergeQueues::Command#retry_checks!]
    sig { override.params(entry: Entry).returns(GenericResult) }
    def retry_checks!(entry)
      @actions << Action.for(entry:, name: Action::Name::RetryChecks)

      @implementation.retry_checks!(entry)
    end

    # @see [MergeQueues::Command#update!]
    sig { override.params(entries: T::Array[Entry]).returns(GenericResult) }
    def update!(entries)
      @actions.concat(entries.map do |entry|
        Action.for(
          entry:,
          name: Action::Name::Update,
          state: entry.state,
        )
      end)

      @implementation.update!(entries)
    end

    # @see [MergeQueues::Command#create_ref!]
    sig { override.params(entry: Entry, base_sha: String, method: IConfiguration::MergeMethod).returns(CreateRefResult) }
    def create_ref!(entry, base_sha:, method:)
      @actions << Action.for(entry:, name: Action::Name::CreateRef)

      @implementation.create_ref!(entry, base_sha:, method:)
    end

    # @see [MergeQueues::Command#request_checks!]
    sig { override.params(entry: Entry, create_ref_result: Result::CreateRefSuccess).returns(GenericResult) }
    def request_checks!(entry, create_ref_result:)
      @actions << Action.for(entry:, name: Action::Name::RequestChecks)

      @implementation.request_checks!(entry, create_ref_result:)
    end

    # @see [MergeQueues::Command#recalculate_positions!]
    sig { override.params(entries: EntryList).returns(GenericResult) }
    def recalculate_positions!(entries)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::RecalculatePositions)
      end)

      @implementation.recalculate_positions!(entries)
    end

    # @see [MergeQueues::Command#store_merge_conflict!]
    sig { override.params(entry: Entry, conflict: Result::MergeConflictError).returns(GenericResult) }
    def store_merge_conflict!(entry, conflict:)
      @actions << Action.for(entry:, name: Action::Name::StoreMergeConflict)

      @implementation.store_merge_conflict!(entry, conflict:)
    end

    # Deliver webhooks related to subscribing to the Merge Queue.
    sig { override.params(payload: WebHook).returns(GenericResult) }
    def dispatch_webhook!(payload)
      @actions << Action.new(
        pull_request_number: payload.pull_request_number,
        merge_queue_entry_id: payload.merge_queue_entry_id,
        name: Action::Name::DispatchWebhook,
        hook_payload: payload,
      )

      @implementation.dispatch_webhook!(payload)
    end

    # Delete the refs associated with the Entries.
    sig { override.params(entries: T::Array[T.any(Entry, MergeQueueEntry)]).returns(GenericResult) }
    def delete_refs!(entries)
      @actions.concat(entries.map do |entry|
        Action.for(entry:, name: Action::Name::DeleteRef)
      end)

      @implementation.delete_refs!(entries)
    end

    # @see [MergeQueues::Command#feature_enabled?]
    sig { override.params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature) = @implementation.feature_enabled?(feature)
  end
end
