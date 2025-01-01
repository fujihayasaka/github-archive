# typed: true
# frozen_string_literal: true

class ReviewRequest < ApplicationRecord::Domain::IssuesPullRequests
  module AssociationExtension
    include GitHub::Memoizer

    # Public: Returns reviewers with pending requests from the existing
    # collection.
    #
    # Excludes any reviewers whose requests are marked for deletion when the
    # parent is saved.
    #
    # Returns the PendingReviewersSet of reviewers (i.e. Users and Teams).
    memoize def pending_reviewers
      PendingReviewersSet.new(self)
    end

    # Public: Helper method for setting pending requests by passing in
    # reviewers. Changes will be persisted when the parent is saved.
    #
    # Any existing pending reviewers, if not passed, will be marked for removal.
    #
    # Ignores any reviewers who are not allowed to be requested for review.
    #
    # Returns the PendingReviewersSet of reviewers (i.e. Users and Teams).
    def pending_reviewers=(reviewers)
      pending_reviewers.replace(reviewers)
    end

    # Public: Adds a new reviewer and records the supplied reasons. If the
    # reviewer is already requested, a new request will not be made and the
    # reasons will not be recorded.
    #
    # reviewer  - The User or Team to request review from.
    # reasons   - (Optional) A Hash of reasons grouped by their type.
    #
    # Example
    #
    #   add_pending_reviewer_with_reasons(team, reasons: {
    #     codeowners: [{tree_oid: "0123456", path: "CODEOWNERS", line: 42, pattern: "*"}]
    #   })
    #
    # Returns true if the request already exists, false if the request could not be made, and the request itself if successful.
    def add_pending_reviewer_with_reasons(reviewer, reasons: {})
      return true if pending_reviewers.include?(reviewer)

      pending_reviewers.add(reviewer, reasons: reasons)
      request = T.unsafe(self).find { |req| req.reviewer == reviewer }

      request || false
    end

    class PendingReviewersSet
      include Enumerable

      ADDED = :added
      REMOVED = :removed

      attr_reader :relation, :pull_request

      def initialize(relation)
        @relation = relation
        @pull_request = relation.proxy_association.owner
      end

      def each(&block)
        pending_reviewers.each(&block)
      end

      def replace(reviewers)
        reconcile(filter(reviewers))
      end

      def add(reviewer, reasons: {})
        reconcile(pending_reviewers | filter([reviewer])) do |action, request|
          next unless action == ADDED && request.reviewer == reviewer

          request.reasons_by_type = reasons
        end
      end

      def merge(reviewers)
        reconcile(pending_reviewers | filter(reviewers))
      end

      private

      def reconcile(finalized_reviewers)
        relation.reload if relation.all?(&:persisted?)
        existing_reviewers = pending_reviewers
        to_add = finalized_reviewers - existing_reviewers
        to_remove = existing_reviewers - finalized_reviewers
        to_reassign = Set.new

        # Add requests for newly finalized reviewers
        to_add.each do |reviewer|
          reassigned_request = reviewer.try(:review_request_assigned_from)
          to_reassign << reassigned_request if reassigned_request

          request = relation.build(reviewer: reviewer, deferred: false, assigned_from_review_request: reassigned_request)
          yield [ADDED, request] if block_given?
        end

        # Remove any non-finalized reviewers (if we have permission)
        pending_requests.each do |request|
          next unless to_remove.include?(request.reviewer) && pull_request.review_request_removable?(request)

          if request.persisted?
            request.dismiss(via_assignment: to_reassign.include?(request))
          else
            relation.delete(request)
          end

          yield [REMOVED, request] if block_given?
        end

        self
      end

      def filter(reviewers)
        pull_request.filter_allowed_reviewers(reviewers)
      end

      def pending_requests
        relation.select do |request|
          request.pending? && !request.marked_for_destruction?
        end
      end

      def pending_reviewers
        pending_requests.map(&:reviewer).uniq
      end
    end
  end
end
