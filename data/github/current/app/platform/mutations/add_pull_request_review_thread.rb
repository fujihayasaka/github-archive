# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddPullRequestReviewThread < Platform::Mutations::Base
      description "Adds a new thread to a pending Pull Request Review."

      minimum_accepted_scopes ["public_repo"]

      argument :path, String, "Path to the file being commented on.", required: false
      argument :body, String, "Body of the thread's first comment.", required: true
      argument :pull_request_id, ID, "The node ID of the pull request reviewing", required: false, loads: Objects::PullRequest, as: :pull
      argument :pull_request_review_id, ID, "The Node ID of the review to modify.", required: false, loads: Objects::PullRequestReview, as: :review
      argument :diff_range, Inputs::DiffRange, "The diff range on which the thread was left. Default is from the base of the pull request to the head of the review.", required: false
      argument :line, Integer, "The line of the blob to which the thread refers, required for line-level threads. The end of the line range for multi-line comments.", required: false
      argument :side, Enums::DiffSide, "The side of the diff on which the line resides. For multi-line comments, this is the side for the end of the line range.", default_value: :right, required: false
      argument :start_line, Integer, "The first line of the range to which the comment refers.", required: false
      argument :start_side, Enums::DiffSide, "The side of the diff on which the start line resides.", default_value: :right, required: false
      argument :submit_review, Boolean, "True to mark this review as submitted", required: false, default_value: false, visibility: :internal
      argument :subject_type, Enums::PullRequestReviewThreadSubjectType, "The level at which the comments in the corresponding thread are targeted, can be a diff line or a file", required: false, default_value: "line"

      with_options(feature_flag: :graphql_pr_comment_positioning, required: false) do
        argument :file_positioning, Inputs::CommentPositionFileInput, "Positioning on a file inputs"
        argument :line_positioning, Inputs::CommentPositionLineInput, "Positioning on a line inputs"
        argument :multiline_positioning, Inputs::CommentPositionMultilineInput, "Positioning on a multiline inputs"
      end

      error_fields
      field :thread, Objects::PullRequestReviewThread, "The newly created thread.", null: true
      field :pull_request_thread, Objects::PullRequestThread, "the newly create pull request thread node.", null: true, visibility: :internal

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, review: nil, pull: nil, **)
        if review
          review.async_pull_request.then do |pull|
            permission.async_repo_and_org_owner(pull).then do |repo, org|
              permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        elsif pull
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:create_pull_request_comment, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          false
        end
      end

      def resolve(path: nil, body:, line: nil, side:, start_side: :right, submit_review: false, review: nil, pull: nil, start_line: nil, diff_range: {}, subject_type: "line", file_positioning: nil, line_positioning: nil, multiline_positioning: nil)
        author = context[:viewer]
        pull = T.let(pull, T.nilable(PullRequest))
        review = T.let(review || pull&.pending_review_for(user: author), T.nilable(PullRequestReview))

        # We swapped `path` to be optional with the addition of the new positional data. This validation ensures that
        # it is still required if none of the new positioning fields are used.
        if path.blank? && (file_positioning.nil? && line_positioning.nil? && multiline_positioning.nil?)
          raise Errors::Validation, "path required"
        end

        repository = T.let(pull&.head_repository, T.nilable(Repository))
        if repository&.feature_enabled?(:graphql_pr_comment_positioning)
          unless pull && review
            raise Errors::Validation, "Review or Pull Request required."
          end

          positioning = if file_positioning
            file_positioning.to_h.merge(type: "file")
          elsif line_positioning
            line_positioning.to_h.merge(type: "line")
          elsif multiline_positioning
            multiline_positioning.to_h.merge(type: "multiline")
          end

          if positioning
            diff_range = diff_range&.to_h || {}

            params = PullRequests::CommentPosition::Legacy::Parameters.new(
              positioning:,
              start_commit_oid: diff_range[:start_commit_oid] || pull.base_sha,
              end_commit_oid: diff_range[:end_commit_oid] || pull.head_sha,
              base_commit_oid: diff_range[:base_commit_oid] || pull.merge_base || pull.base_sha,
            ).call

            case params
            when PullRequests::CommentPosition::Legacy::Parameters::Attributes
              path = params.path
              side = params.side
              start_side = params.start_side
              line = params.line
              start_line = params.start_line
              subject_type = params.subject_type
            when PullRequests::CommentPosition::Legacy::Parameters::Errors
              raise Errors::Unprocessable.new("error `#{params.serialize}` at for positioning")
            end
          end
        elsif !review
          raise Errors::Validation, "Review or Pull Request required."
        end

        if !line && subject_type == "line"
          raise Errors::Validation, "Line required for for line-level threads"
        end

        ReviewThreadCreator.new(author:, path:, body:, line:, start_line:, side:, start_side:, submit_review:, review:, pull:, diff_range:, subject_type:).async_create_thread.then do |thread, comment|
          if thread.persisted?
            pull_request_thread = Platform::Models::PullRequestThread.new(thread)

            { thread: thread, pull_request_thread: pull_request_thread, errors: [] }
          else
            # this just says there is a problem with the comments and is useless from the perspective of integrators
            thread.errors.delete(:review_comments)
            client_errors = mapped_client_errors(thread) + mapped_client_errors(comment)
            { thread: nil, pull_request_thread: nil, errors: client_errors }
          end
        end
      end

      CLIENT_ERRORS_MAPPING = {
        pull_request_review_id: ["pullRequestReviewId"],
        pull_request_review_thread_id: ["pullRequestReviewId"],
        start_commit_oid: %w[diffRange startCommitOid],
        end_commit_oid: %w[diffRange endCommitOid],
        base_commit_oid: %w[diffRange baseCommitOid],
        line: ["line"],
        start_line: ["startLine"],
        body: ["body"],
        path: ["path"],
      }.freeze

      def mapped_client_errors(comment)
        client_errors = T.let([], Array)

        CLIENT_ERRORS_MAPPING.each_pair do |ar_attribute, path|
          if comment.errors.include?(ar_attribute)
            client_errors += build_client_errors(path, comment.errors[ar_attribute])
          end
        end

        client_errors
      end

      def build_client_errors(path, messages, prefix: "input")
        attribute = path.last.underscore
        messages.map do |message|
          {
            path: ["input", path].flatten,
            message: "#{attribute.titleize.downcase.capitalize} #{message}",
            attribute: attribute,
            short_message: message,
          }
        end
      end
    end
  end
end
