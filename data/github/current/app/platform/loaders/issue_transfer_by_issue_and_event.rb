# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    # Loads all IssueTransfer records for a given issue by walking the
    # transfer chain backwards.
    #
    # When an issue is transferred through multiple repos (A → B → C), each
    # hop creates an IssueTransfer record. However, the IssueTransfer for
    # earlier hops (e.g. A→B) has new_issue_id pointing to the intermediate
    # (now-destroyed) issue, not the final one. This loader walks the chain
    # backwards from the final issue and returns all transfers in
    # chronological order (oldest first).
    #
    # Scoped by issue_id so that all TransferredEvents on the same issue's
    # timeline share a single loader instance and chain traversal.
    #
    # The key is the IssueEvent ID of the TransferredEvent, which is matched
    # to the correct IssueTransfer by chronological position (the Nth
    # TransferredEvent in timeline order corresponds to the Nth transfer
    # in the chain).
    #
    # NOTE: This loader does not perform authorization checks. Callers must
    # verify the viewer has access to the relevant repository before using
    # the returned data.
    class IssueTransferByIssueAndEvent < Platform::Loader
      sig { params(issue_id: Integer, event_id: Integer).returns(Promise[T.nilable(IssueTransfer)]) }
      def self.load(issue_id, event_id)
        self.for(issue_id).load(event_id)
      end

      sig { params(issue_id: Integer).void }
      def initialize(issue_id)
        @issue_id = issue_id
      end

      sig { params(event_ids: T::Array[Integer]).returns(T::Hash[Integer, T.nilable(IssueTransfer)]) }
      def fetch(event_ids)
        # Walk the chain to get all transfers in chronological order (oldest first)
        transfers = collect_transfer_chain

        # Get the TransferredEvents for this issue in chronological order.
        # IssueEvent has `default_scope { includes(:issue_event_detail) }` which
        # produces a LEFT JOIN on has_one associations when combined with pluck.
        # Since we only need IDs, drop the eager-load to keep the query simple.
        transferred_events = IssueEvent
          .where(issue_id: @issue_id, event: "transferred")
          .unscope(:includes)
          .order(:created_at, :id)
          .pluck(:id)

        # Build a mapping: event_id → transfer (by position)
        event_to_transfer = T.let({}, T::Hash[Integer, T.nilable(IssueTransfer)])
        transferred_events.each_with_index do |eid, idx|
          event_to_transfer[eid] = transfers[idx] if idx < transfers.length
        end

        # Return results for the requested event_ids
        event_ids.each_with_object({}) do |eid, result|
          result[eid] = event_to_transfer[eid]
        end
      end

      private

      sig { returns(T::Array[IssueTransfer]) }
      def collect_transfer_chain
        chain = T.let([], T::Array[IssueTransfer])
        current_issue_id = T.let(@issue_id, Integer)

        IssueTransfer::DEFAULT_TRANSFER_TRAVERSAL_DEPTH.times do
          transfer = IssueTransfer.find_by(new_issue_id: current_issue_id)
          break unless transfer

          chain.unshift(transfer) # prepend to get chronological order
          current_issue_id = transfer.old_issue_id
        end

        chain
      end
    end
  end
end
