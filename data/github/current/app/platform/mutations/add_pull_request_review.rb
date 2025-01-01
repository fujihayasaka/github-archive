# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestReview < Platform::Mutations::Base
      DeprecationNotice = {
        start_date: Date.new(2023, 4, 1),
          reason: "We are deprecating comment fields that use diff-relative positioning",
          superseded_by: "use the `threads` argument instead",
          owner: "aharpole",
      }
      description "Adds a review to a Pull Request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Node ID of the pull request to modify.", required: true, loads: Objects::PullRequest, as: :pull
      argument :commitOID, Scalars::GitObjectID, "The commit OID the review pertains to.", required: false,
        as: :commit_oid
      argument :body, String, "The contents of the review body comment.", required: false
      argument :event, Enums::PullRequestReviewEvent, "The event to perform on the pull request review.", required: false
      argument :comments, [Inputs::DraftPullRequestReviewComment, null: true], "The review line comments.", required: false, deprecated: DeprecationNotice
      argument :threads, [Inputs::DraftPullRequestReviewThread, null: true], "The review line comment threads.", required: false

      field :review_edge, Objects::PullRequestReview.edge_type, "The edge from the pull request's review connection.", null: true

      field :pull_request_review, Objects::PullRequestReview, "The newly created pull request review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull:, **inputs)
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull:, **inputs)
        repo = T.let(pull.repository, Repository)

        if !(repo.readable_by?(context[:viewer]) || repo.resources.pull_requests.writable_by?(context[:viewer]))
          raise Errors::Forbidden.new("Viewer does not have permission to review this pull request.")
        end

        comparison = PullRequest::Comparison.find(
          pull: pull,
          start_commit_oid: pull.merge_base,
          end_commit_oid: inputs[:commit_oid] || pull.head_sha,
          base_commit_oid: pull.merge_base,
        )

        threads = inputs[:threads] || []

        use_positioning = repo.feature_flag_enabled?(:graphql_pr_comment_positioning, default: false)

        # Since line/path are now not required due to the new positioning fields, we must validate at runtime that the
        # inputs are valid.
        threads.each.with_index do |thread, i|
          path, line, *positionings = thread.to_h.values_at(:path, :line, :file_positioning, :line_positioning, :multiline_positioning)

          if positionings.empty?
            if path.blank?
              raise Errors::Validation.new("threads.#{i}.path cannot be blank")
            elsif line.blank?
              raise Errors::Validation.new("threads.#{i}.line cannot be blank")
            end
          end
        end

        if use_positioning
          comments = (inputs[:comments] || []) + transform_threads(threads, comparison:)
        else
          comments = (inputs[:comments] || []) + (threads)
        end

        raise Errors::Validation.new("The commitOID is not part of the pull request") unless comparison

        result = Platform::LoaderTracker.ignore_association_loads do
          PullRequestReview::Creator.execute(pull_request: pull,
            user: context[:viewer],
            body: inputs[:body],
            comments: comments,
            event: inputs[:event],
            pull_comparison: comparison,
          )
        end

        review = result.review

        if result.success?
          connection = Platform::ConnectionWrappers::Relation.new(pull.reviews.scoped, context: context)
          {
            pull_request_review: review,
            review_edge: GraphQL::Pagination::Connection::Edge.new(review, connection),
          }
        else
          raise Errors::Unprocessable.new(result.errors.to_sentence)
        end
      end

      private

      sig { params(threads: T.untyped, comparison: T.nilable(PullRequest::Comparison)).returns(T::Array[ActiveSupport::HashWithIndifferentAccess]) }
      def transform_threads(threads, comparison:)
        threads.map.with_index do |thread, i|
          hash = thread.to_h.with_indifferent_access

          next hash if comparison.nil?

          file, line, multiline, body = hash.values_at(:file_positioning, :line_positioning, :multiline_positioning, :body)

          positioning = if file
            file.merge(type: "file")
          elsif line
            line.merge(type: "line")
          elsif multiline
            multiline.merge(type: "multiline")
          end

          next hash unless positioning

          params = PullRequests::CommentPosition::Conversion::ParamsToArguments.convert(
            positioning:,
            base_commit_oid: comparison.start_commit.oid,
            head_commit_oid: comparison.end_commit.oid,
          )

          case params
          when PullRequests::CommentPosition::Conversion::ParamsToArguments::Arguments
            params.serialize.with_indifferent_access.without(:positioning).merge(body:)
          when PullRequests::CommentPosition::Errors
            raise Errors::Unprocessable.new("error `#{params.to_error_message}` at threads position #{i}")
          end
        end
      end
    end
  end
end
