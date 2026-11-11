# typed: true
# frozen_string_literal: true

module MemexProjectColumnValue::ReviewerHashable
  extend ActiveSupport::Concern

  included do
    # Internal: when comparing whether a user or team has either been requested
    # for review of a Pull Request or has submitted a review, we need to have a
    # way to make the resource unique to avoide sending duplicates to the
    # client. This method takess in a User or a Team (or a hash representing)
    # eitehr of those models and builds a string out of their immutable
    # attributes so that callers can run `uniq` on the result.
    #
    # Returns a String.
    def hashed_reviewer(resource)
      return "#{resource[:type]}-#{resource[:id]}" if resource.is_a?(Hash)

      "#{reviewer_safe_type(resource)}-#{resource.id}"
    end

    private def reviewer_safe_type(reviewer)
      reviewer.respond_to?(:type) ? reviewer.type : reviewer.class
    end

    # Internal: upon recieving an instance of a ReviewRequest, build a hash to
    # send to the Memex client.
    #
    # Returns a Hash.
    def review_request_hash(review_request)
      {
        type: "ReviewRequest",
        status: "pending",
        reviewer: review_request.reviewer.memex_reviewer_hash
      }
    end

    # Internal: upon recieving an instance of a PullRequestReview, build a hash
    # to send to the Memex client.
    #
    # Returns a Hash.
    def pull_request_review_hash(pull_request_review)
      {
        type: "PullRequestReview",
        status: PullRequestReview.state_name(pull_request_review.state),
        reviewer: pull_request_review.safe_user.memex_reviewer_hash
      }
    end
  end
end
