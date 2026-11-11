# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestReview < Platform::Mutations::Base
      docs_category :pulls
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

        comments = inputs[:comments] || []
        threads = inputs[:threads] || []

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

        raise Errors::Validation.new("The commitOID is not part of the pull request") unless comparison

        if repo.feature_flag_enabled?(:graphql_cotd_creation, default: false)
          tags = { mutation: "AddPullRequestReview", repository_id: repo.id, pull_request_id: pull.id, actor_id: context[:viewer]&.id }
          GitHub.logger.with_named_tags(tags) do
            # If GitHub Actions GITHUB_TOKEN is making the request, check whether
            # Actions workflows are allowed to approve PRs. TODO: Lift this to the top of this resolver when this feature flag is
            # fully promoted.
            if actions_user_requesting_approval?(context[:viewer], inputs[:event]) && disallow_actions_approvals?(pull)
              raise Errors::Unprocessable.new("GitHub Actions is not permitted to approve pull requests.")
            end

            # Create a review object using the inputs from the mutation.
            head_sha = comparison.end_commit.oid
            review = pull.reviews.build(
              user: context[:viewer],
              head_sha: head_sha,
              merge_base_sha: pull.find_best_merge_base_sha(head_sha: head_sha),
              body: inputs[:body]
            )

            parameters = comments.map(&:to_h) + transform_threads(threads:, comparison:).compact

            result = PullRequests::ReviewComments::Create.create_many_from_parameters(
              pull_request: pull,
              review:,
              review_event: inputs[:event],
              actor: context[:viewer],
              destination_base_commit_oid: review.merge_base_sha,
              destination_head_commit_oid: review.head_sha,
              parameters:,
              only_changed_files: repo.feature_flag_enabled?(:cotd_comment_only_on_changed_files, default: false)
            )

            case result
            when PullRequests::ReviewComments::Create::Error
              raise Errors::Unprocessable.new(result.errors.full_messages.to_sentence)
            when PullRequests::ReviewComments::Create::BulkSuccess
              connection = Platform::ConnectionWrappers::Relation.new(pull.reviews.scoped, context: context)
              {
                pull_request_review: review,
                review_edge: GraphQL::Pagination::Connection::Edge.new(review, connection),
              }
            else
              T.absurd(result)
            end
          end
        else
          comments = comments + threads
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
      end

      private

      sig { params(threads: T.untyped, comparison: PullRequest::Comparison).returns(T::Array[ActiveSupport::HashWithIndifferentAccess]) }
      def transform_threads(threads:, comparison:)
        threads.map do |thread|
          hash = thread.to_h.with_indifferent_access

          file, line, multiline, body = hash.values_at(:file_positioning, :line_positioning, :multiline_positioning, :body)
          subject_type = "line"

          positioning = if file
            subject_type = "file"
            file.merge(type: "file")
          elsif line
            subject_type = "line"
            line.merge(type: "line")
          elsif multiline
            subject_type = "line"
            multiline.merge(type: "multiline")
          end

          {
            body:,
            # New positional format.
            positioning:,

            # Previous blob positioning.
            side: hash[:side],
            start_line: hash[:start_line],
            start_side: hash[:start_side] || :right,
            subject_type:,
            line: hash[:line],
            path: hash[:path],
            source_base_commit_oid: comparison.start_commit.oid,
            source_head_commit_oid: comparison.end_commit.oid,
          }
        end
      end

      def actions_user_requesting_approval?(user, event)
        user.can_have_granular_permissions? &&
        (integration = user.try(:integration)) &&
        integration.launch_github_app? &&
        event&.to_sym == :approve
      end

      def disallow_actions_approvals?(pull_request)
        !pull_request.repository.actions_workflow_permission_can_approve_pr? # Actions review does NOT count towards approval
      end
    end
  end
end
