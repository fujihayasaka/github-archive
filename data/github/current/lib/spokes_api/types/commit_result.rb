# typed: true
# frozen_string_literal: true

module SpokesAPI
  module Types
    # CommitResult consolidates the result of a commit creation from multiple Spokes API calls.
    class CommitResult
      # MERGE_STATUSES contains all valid merge statuses from GitHub::Spokes::Proto::Merges::V1::MergeTreesResponse::Status
      MERGE_STATUSES = %i[STATUS_SUCCESS STATUS_MERGE_CONFLICT STATUS_ALREADY_MERGED].freeze

      # status contains the status of the commit creation:
      # - :STATUS_SUCCESS if the commit was created successfully
      # - :STATUS_MERGE_CONFLICT if there were merge conflicts during MergeTrees
      # - :STATUS_ALREADY_MERGED if the branches were already merged during MergeTrees
      sig { returns(Symbol) }
      attr_reader :status

      # oid contains the OID of the newly created commit when status is :STATUS_SUCCESS
      sig { returns(T.nilable(String)) }
      attr_reader :oid

      # conflicts contains any merge conflicts from MergeTrees call in the format of
      # GitHub::Spokes::Proto::Merges::V1::MergeTreesResponse::MergeConflictResult when status is :STATUS_MERGE_CONFLICT
      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :conflicts

      sig do
        params(
          status: T.any(Symbol, Integer),
          oid: T.nilable(String),
          conflicts: T.nilable(T::Hash[Symbol, T.untyped])
        ).void
      end
      def initialize(status:, oid: nil, conflicts: nil)
        lookup_status = status.is_a?(Integer) ? GitHub::Spokes::Proto::Merges::V1::MergeTreesResponse::Status.lookup(status) : status
        raise ArgumentError, "unexpected commit status #{lookup_status}" unless MERGE_STATUSES.include?(lookup_status)

        @oid = oid
        @status = lookup_status
        @conflicts = conflicts || {}
      end
    end
  end
end
