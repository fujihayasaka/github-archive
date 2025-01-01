# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Interface for encapsulating the state of an Entry. This will both be a description of the state and all data
  # required to make decisions for this state.
  module Entry::State
    extend T::Helpers
    extend T::Sig

    abstract!
    sealed!

    requires_ancestor { Object }

    Classes = T.type_alias do
      T.any(
        T.class_of(Waiting),
        T.class_of(Queued),
        T.class_of(AwaitingChecks),
        T.class_of(Mergeable),
        T.class_of(Unmergeable),
      )
    end

    sig { params(options: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Hash[String, T.untyped]) }
    def as_json(options = {})
      json = super

      if (options || {}).fetch(:except, []).include?("name")
        json
      else
        json.merge("name" => name)
      end
    end

    sig { returns(String) }
    def name
      self.class.name&.demodulize
    end

    sig { params(state: Entry::State).returns(Integer) }
    def self.serialize(state)
      case state
      when Waiting then Waiting::VALUE
      when Queued then Queued::VALUE
      when AwaitingChecks then AwaitingChecks::VALUE
      when Mergeable then Mergeable::VALUE
      when Unmergeable then Unmergeable::VALUE
      else
        T.absurd(state)
      end
    end

    sig { params(value: Integer).returns(Classes) }
    def self.deserialize(value)
      case value
      when Waiting::VALUE then Waiting
      when Queued::VALUE then Queued
      when AwaitingChecks::VALUE then AwaitingChecks
      when AwaitingChecks::REMOVED_FAILED_LATEST_CHECK_ATTEMPT_VALUE then AwaitingChecks
      when Mergeable::VALUE then Mergeable
      when Mergeable::REMOVED_LOCKED_VALUE then Mergeable
      when Unmergeable::VALUE then Unmergeable
      else
        raise ArgumentError, "Unknown state value #{value.inspect}"
      end
    end

    sig { returns(Integer) }
    def serialize
      Entry::State.serialize(self)
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      other.class == self.class
    end

    # An Entry that has been added with Auto Merge.
    class Waiting
      include Entry::State
      extend T::Sig

      VALUE = 0
      HYDRO_ENUM_VALUE = :WAITING
      GRAPHQL_ENUM_VALUE = :AWAITING_CHECKS # This is a legacy value that we need to keep for backwards compatibility.

      sig { returns(Symbol) }
      def self.primer_color
        :attention
      end

      sig { returns(Symbol) }
      def self.octicon_name
        :"git-merge-queue"
      end

      sig { returns(String) }
      def self.description
        "Waiting"
      end
    end

    # An Entry awaiting to be evaluated by the Merge Queue.
    class Queued
      include Entry::State
      extend T::Sig

      VALUE = 1
      HYDRO_ENUM_VALUE = :QUEUED
      GRAPHQL_ENUM_VALUE = :QUEUED

      sig { returns(Symbol) }
      def self.primer_color
        :attention
      end

      sig { returns(Symbol) }
      def self.octicon_name
        :"git-merge-queue"
      end

      sig { returns(String) }
      def self.description
        "Waiting"
      end
    end

    # An Entry who has created the Ref object and is awaiting a response from CI providers.
    class AwaitingChecks < T::Struct
      extend T::Sig
      include Entry::State
      VALUE = 2
      REMOVED_FAILED_LATEST_CHECK_ATTEMPT_VALUE = 4
      HYDRO_ENUM_VALUE = :AWAITING_CHECKS
      GRAPHQL_ENUM_VALUE = :AWAITING_CHECKS

      const :checks_requested_at, ActiveSupport::TimeWithZone

      sig { returns(Symbol) }
      def self.primer_color
        :attention
      end

      sig { returns(Symbol) }
      def self.octicon_name
        :"dot-fill"
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        if other.is_a?(AwaitingChecks)
          checks_requested_at == other.checks_requested_at
        else
          false
        end
      end

      sig { returns(String) }
      def self.description
        "Waiting for required checks"
      end
    end

    # An Entry who has satisified all of the required checks and has no conflicts.
    class Mergeable
      extend T::Sig
      include Entry::State

      VALUE = 3
      REMOVED_LOCKED_VALUE = 6
      HYDRO_ENUM_VALUE = :MERGEABLE
      GRAPHQL_ENUM_VALUE = :MERGEABLE

      sig { returns(Symbol) }
      def self.primer_color
        :success
      end

      sig { returns(Symbol) }
      def self.octicon_name
        :"check"
      end

      sig { returns(String) }
      def self.description
        "Ready to merge"
      end
    end

    # An Entry who cannot ever be merged.
    class Unmergeable < T::Struct
      extend T::Sig
      include Entry::State
      VALUE = 5
      HYDRO_ENUM_VALUE = :UNMERGEABLE
      GRAPHQL_ENUM_VALUE = :UNMERGEABLE

      const :reason, Entry::RemovalReason

      sig { returns(Symbol) }
      def self.primer_color
        :danger
      end

      sig { returns(Symbol) }
      def self.octicon_name
        :"x"
      end

      sig { returns(String) }
      def self.description
        "Not mergeable"
      end

      sig { returns(T.attached_class) }
      def self.merge_conflict
        new(reason: Entry::RemovalReason::MergeConflict)
      end

      sig { returns(T.attached_class) }
      def self.failed_checks
        new(reason: Entry::RemovalReason::FailedChecks)
      end

      sig { returns(T.attached_class) }
      def self.checks_timed_out
        new(reason: Entry::RemovalReason::ChecksTimedOut)
      end

      sig { returns(T.attached_class) }
      def self.already_merged
        new(reason: Entry::RemovalReason::AlreadyMerged)
      end

      sig { returns(T.attached_class) }
      def self.git_tree_invalid
        new(reason: Entry::RemovalReason::GitTreeInvalid)
      end

      sig { returns(T.attached_class) }
      def self.invalid_merge_commit
        new(reason: Entry::RemovalReason::InvalidMergeCommit)
      end

      sig { returns(T.attached_class) }
      def self.branch_protections
        new(reason: Entry::RemovalReason::BranchProtections)
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        if other.is_a?(Unmergeable)
          reason == other.reason
        else
          false
        end
      end

      sig { returns(T::Boolean) }
      def merge_conflict?
        reason == Entry::RemovalReason::MergeConflict
      end

      # Are we in a state where our git ref updates will always fail?
      sig { returns(T::Boolean) }
      def unrecoverable_git_failure?
        case current_reason = reason
        when Entry::RemovalReason::BranchProtections,
             Entry::RemovalReason::GitTreeInvalid,
             Entry::RemovalReason::InvalidMergeCommit
          true
        when Entry::RemovalReason::Unknown, Entry::RemovalReason::Manual, Entry::RemovalReason::Merged,
             Entry::RemovalReason::MergeConflict, Entry::RemovalReason::FailedChecks,
             Entry::RemovalReason::ChecksTimedOut, Entry::RemovalReason::AlreadyMerged,
             Entry::RemovalReason::QueueCleared, Entry::RemovalReason::RollBack
          false
        else
          T.absurd(current_reason)
        end
      end
    end
  end
end
