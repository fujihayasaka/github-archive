# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module RequestReviews
        extend T::Helpers

        requires_ancestor { Platform::Mutations::Base }

        # Main resolve logic shared between RequestReviews and RequestReviewsByLogin
        def resolve_request_reviews(pull:, reviewers:, re_request:, union:)
          unless pull.request_review_from(reviewers: reviewers, actor: context[:viewer], re_request: re_request, append: union)
            GitHub.logger.info("Request Reviews validation error: #{pull.errors.full_messages.to_sentence}", "gh.pull_requests.request_reviews_validation_errors" => true)
            raise Errors::Unprocessable.new("Could not add requested reviewers to pull request.")
          end

          reviewers_relation = Platform::LoaderTracker.ignore_association_loads do
            pull.review_requests.pending.scoped
          end

          reviewers_connection = Platform::ConnectionWrappers::Relation.new(reviewers_relation, context: context)

          {
            requested_reviewers_edge: GraphQL::Pagination::Connection::Edge.new(pull, reviewers_connection),
            pull_request: pull,
            actor: context[:viewer],
          }
        end
      end
    end
  end
end
