# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestReviewComment < Platform::Mutations::Base
      DeprecationNotice = {
        start_date: Date.new(2023, 4, 1),
          reason: "We are deprecating the addPullRequestReviewComment mutation",
          superseded_by: "use addPullRequestReviewThread or addPullRequestReviewThreadReply instead",
          owner: "aharpole",
      }
      description "Adds a comment to a review."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The node ID of the pull request reviewing", required: false, loads: Objects::PullRequest, as: :pull, deprecated: DeprecationNotice
      argument :pull_request_review_id, ID, "The Node ID of the review to modify.", required: false, loads: Objects::PullRequestReview, as: :review, deprecated: DeprecationNotice
      argument :commitOID, Scalars::GitObjectID, "The SHA of the commit to comment on.", required: false,
        as: :commit_oid, deprecated: DeprecationNotice
      argument :body, String, "The text of the comment. This field is required", required: false, deprecated: DeprecationNotice
      argument :path, String, "The relative path of the file to comment on.", required: false, deprecated: DeprecationNotice
      argument :position, Integer, "The line index in the diff to comment on.", required: false, deprecated: DeprecationNotice
      argument :in_reply_to, ID, "The comment id to reply to.", required: false, loads: Objects::PullRequestReviewComment, deprecated: DeprecationNotice

      field :comment_edge, Objects::PullRequestReviewComment.edge_type, "The edge from the review's comment connection.", null: true

      field :comment, Objects::PullRequestReviewComment, "The newly created comment.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        if inputs[:body].nil?
          raise Errors::ArgumentError.new "Argument 'body' on mutation 'addPullRequestReviewComment' is required. Expected type String"
        end
        if inputs[:review]
          inputs[:review].async_pull_request.then do |pull|
            permission.async_repo_and_org_owner(pull).then do |repo, org|
              permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        elsif inputs[:pull]
          permission.async_repo_and_org_owner(inputs[:pull]).then do |repo, org|
            permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: inputs[:pull], allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          false
        end
      end

      def resolve(**inputs)
        if inputs[:review]
          review = inputs[:review]
        elsif inputs[:pull]
          review = inputs[:pull].pending_review_for(user: context[:viewer])
        else
          raise Errors::Validation.new("Review or Pull Request required.")
        end

        if !review.pending?
          raise Errors::Validation.new("Review has already been submitted.")
        end
        end_commit_oid = inputs[:commit_oid] || review.pull_request.head_sha
        pull_comparison = PullRequest::Comparison.find(
          pull: review.pull_request,
          start_commit_oid: review.pull_request.merge_base,
          end_commit_oid: end_commit_oid,
          base_commit_oid: review.pull_request.merge_base,
        )

        unless pull_comparison
          raise Errors::Validation.new("The commitOID is not part of the pull request.")
        end

        thread = T.let(nil, T.nilable(PullRequestReviewThread))
        comment = T.let(nil, T.nilable(PullRequestReviewComment))

        Platform::LoaderTracker.ignore_association_loads do
          if !inputs[:in_reply_to]
            thread, comment = review.build_thread_with_comment(
              user: context[:viewer],
              body: inputs[:body],
              diff: pull_comparison.diffs,
              position: inputs[:position].to_i,
              path: inputs[:path],
            )
          else
            parent = inputs[:in_reply_to]
            if parent.pull_request_id != review.pull_request_id
              raise Errors::Validation.new("The inReplyTo comment is not part of the pull request.")
            end

            comment = ReviewThreadReplier.new(
              review: review,
              parent: parent,
              body: inputs[:body],
              user: context[:viewer],
            ).create_reply_comment
          end
        end

        PullRequestReview.transaction do
          raise ActiveRecord::Rollback unless T.must(comment).save # rubocop:disable GitHub/UsePlatformErrors
        end

        if comment&.persisted?
          connection = Platform::ConnectionWrappers::Relation.new(review.review_comments.scoped, context: context)
          {
            comment: comment,
            comment_edge: GraphQL::Pagination::Connection::Edge.new(comment, connection),
          }
        else
          raise Errors::Unprocessable.new(T.must(comment).errors.full_messages.to_sentence)
        end
      end
    end
  end
end
