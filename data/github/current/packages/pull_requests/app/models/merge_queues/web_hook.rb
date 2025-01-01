# typed: strict
# frozen_string_literal: true

module MergeQueues
  module WebHook
    extend T::Helpers

    sealed!
    interface!
    requires_ancestor { Object }
    requires_ancestor { T::Struct }

    sig { abstract.returns(Integer) }
    def pull_request_number; end

    sig { abstract.returns(Integer) }
    def merge_queue_entry_id; end

    class ChecksRequested < T::Struct
      include WebHook

      const :pull_request_number, Integer
      const :merge_queue_entry_id, Integer

      sig { params(entry: Entry).returns(ChecksRequested) }
      def self.for(entry:)
        # NOTE: It's important that we copy the relevant information from
        #  the Entry here, instead of holding a reference to the Entry
        #  beacuse the Entry can change before the web hook is dispatched.
        new(
          pull_request_number: entry.pull_request_number,
          merge_queue_entry_id: entry.merge_queue_entry_id,
        )
      end

      sig { returns(String) }
      def to_s
        "checks requested"
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(ChecksRequested) &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        other.class == ChecksRequested &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id
      end

      sig { returns(Integer) }
      def hash
        [self.class, pull_request_number, merge_queue_entry_id].hash
      end
    end

    class Dequeued < T::Struct
      include WebHook

      const :pull_request_number, Integer
      const :pull_request_id, Integer
      const :merge_queue_entry_id, Integer
      const :reason, Entry::RemovalReason
      const :actor, T.nilable(User)

      sig { params(entry: Entry, reason: Entry::RemovalReason, actor: T.nilable(User)).returns(Dequeued) }
      def self.for(entry:, reason:, actor: nil)
        new(
          pull_request_id: entry.pull_request_id,
          pull_request_number: entry.pull_request_number,
          merge_queue_entry_id: entry.merge_queue_entry_id,
          reason:,
          actor:,
        )
      end

      sig { params(entry: MergeQueueEntry, reason: Entry::RemovalReason, actor: T.nilable(User)).returns(Dequeued) }
      def self.for_model(entry:, reason:, actor: nil)
        new(
          pull_request_id: entry.pull_request_id,
          pull_request_number: T.must(entry.pull_request).number,
          merge_queue_entry_id: entry.id,
          reason:,
          actor:,
        )
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(ChecksRequested) &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        other.class == ChecksRequested &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id
      end

      sig { returns(Integer) }
      def hash
        [self.class, pull_request_number, merge_queue_entry_id].hash
      end

      sig { returns(String) }
      def to_s
        "dequeued because #{reason.serialize}"
      end
    end

    class Destroyed < T::Struct
      include WebHook

      class MissingDataError < StandardError; end

      class Reason < T::Enum
        # NOTE: This enum must remain in sync with the API definition in
        #  `app/api/description/components/schemas/webhooks/merge-group-destroyed.yaml`
        enums do
          Merged = new(:merged)
          Invalidated = new(:invalidated)
          Dequeued = new(:dequeued)
        end
      end

      const :pull_request_number, Integer
      const :pull_request_id, Integer
      const :merge_queue_entry_id, Integer
      const :head_ref, String
      const :head_sha, String
      const :base_sha, String
      const :checks_requested_at, T.nilable(ActiveSupport::TimeWithZone)
      prop :reason, Reason

      sig { params(entry: T.any(Entry, MergeQueueEntry), reason: T.any(Reason, Entry::RemovalReason)).returns(Destroyed) }
      def self.for(entry:, reason:)
        # NOTE: It's important that we copy the relevant information from
        #  the Entry here, instead of holding a reference to the Entry
        #  beacuse the Entry can change before the web hook is dispatched.

        case entry
        when Entry
          merge_queue_entry_id = entry.merge_queue_entry_id
          pull_request_number = entry.pull_request_number
        when MergeQueueEntry
          merge_queue_entry_id = entry.id
          pull_request_number = T.must(entry.pull_request).number
        else
          T.absurd(entry)
        end

        head_ref = entry.head_ref
        head_sha = entry.head_sha
        base_sha = entry.base_sha
        checks_requested_at = entry.checks_requested_at

        if head_ref.nil? || head_sha.nil? || base_sha.nil?
          missing_fields = { head_ref:, head_sha:, base_sha:, }
            .select { _2.nil? }.keys

          raise MissingDataError.new(
            "Entry ##{merge_queue_entry_id} cannot be used to build a "\
            "destroyed Web hook payload: it is in the #{entry.state.class.name} "\
            "state, and is missing required values: #{missing_fields.to_sentence}"
          )
        end

        case reason
        when Reason::Merged, Entry::RemovalReason::Merged
          reason = Reason::Merged
        when Reason::Dequeued, Entry::RemovalReason::AlreadyMerged,
            Entry::RemovalReason::BranchProtections, Entry::RemovalReason::ChecksTimedOut,
            Entry::RemovalReason::FailedChecks, Entry::RemovalReason::GitTreeInvalid,
            Entry::RemovalReason::Manual, Entry::RemovalReason::MergeConflict,
            Entry::RemovalReason::QueueCleared, Entry::RemovalReason::RollBack,
            Entry::RemovalReason::InvalidMergeCommit, Entry::RemovalReason::Unknown
          reason = Reason::Dequeued
        when Reason::Invalidated
          reason = Reason::Invalidated
        else
          T.absurd(reason)
        end

        new(
          pull_request_id: entry.pull_request_id,
          pull_request_number:,
          merge_queue_entry_id:,
          head_ref:,
          head_sha:,
          base_sha:,
          reason:,
          checks_requested_at:,
        )
      end

      sig { returns(String) }
      def to_s
        "destroyed because #{reason.serialize}"
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(Destroyed) &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def eql?(other)
        other.class == Destroyed &&
          other.pull_request_number == pull_request_number &&
          other.merge_queue_entry_id == merge_queue_entry_id
      end

      sig { returns(Integer) }
      def hash
        [self.class, pull_request_number, merge_queue_entry_id].hash
      end
    end
  end
end
