# typed: strict
# frozen_string_literal: true

module MergeQueues
  class Entry::RemovalReason < T::Enum
    extend T::Sig

    enums do
      Unknown = new(:unknown)
      Manual = new(:manual)
      Merged = new(:merged)
      MergeConflict = new(:merge_conflict)
      FailedChecks = new(:failed_checks)
      ChecksTimedOut = new(:checks_timed_out)
      AlreadyMerged = new(:already_merged)
      QueueCleared = new(:queue_cleared)
      BranchProtections = new(:branch_protection_failure)
      GitTreeInvalid = new(:git_tree_invalid)
      InvalidMergeCommit = new(:invalid_merge_commit)
      RollBack = new(:roll_back)
    end

    sig { params(value: T.nilable(Integer)).returns(Entry::RemovalReason) }
    def self.from_i(value)
      each_value do |reason|
        if reason.to_i == value
          return reason
        end
      end

      Unknown
    end

    sig { override(allow_incompatible: true).params(value: T.nilable((T.any(Symbol, String)))).returns(Entry::RemovalReason) } # rubocop:disable Sorbet/AllowIncompatibleOverride
    def self.deserialize(value)
      case value
      when :merge then Merged
      when :ci_failure then FailedChecks
      when :queue_clear then QueueCleared
      when "", nil, :"" then Unknown
      when String then deserialize(value.to_sym)
      else
        super
      end
    rescue KeyError => e
      Failbot.report!(e)
      Unknown
    end

    sig { returns(Integer) }
    def to_i
      case self
      when Unknown then 0
      when Manual then 1
      when Merged then 2
      when MergeConflict then 3
      when FailedChecks then 4
      when ChecksTimedOut then 5
      when AlreadyMerged then 6
      when QueueCleared then 7
      when RollBack then 8
      when BranchProtections then 9
      when GitTreeInvalid then 10
      when InvalidMergeCommit then 11
      else
        T.absurd(self)
      end
    end

    # Needs to be in sync with:
    # Hydro::Schemas::Github::MergeQueue::V1::MergeQueueEntryEvent::RemovalReason
    sig { returns(Symbol) }
    def to_hydro_enum_value
      case self
      when Unknown then :UNKNOWN_REMOVAL_REASON
      when Manual then :MANUAL
      when Merged then :MERGE
      when MergeConflict then :MERGE_CONFLICT
      when FailedChecks then :CI_FAILURE
      when ChecksTimedOut then :CI_TIMEOUT
      when AlreadyMerged then :ALREADY_MERGED
      when QueueCleared then :QUEUE_CLEARED
      when RollBack then :ROLL_BACK
      when BranchProtections then :BRANCH_PROTECTIONS
      when GitTreeInvalid then :GIT_TREE_INVALID
      when InvalidMergeCommit then :INVALID_MERGE_COMMIT
      else
        T.absurd(self)
      end
    end

    sig { override(allow_incompatible: true).returns(Symbol) } # rubocop:disable Sorbet/AllowIncompatibleOverride
    def serialize
      super
    end

    sig { returns(String) }
    def to_s
      serialize.to_s
    end
  end
end
