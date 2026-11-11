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
        pull = T.let(pull || review&.pull_request, T.nilable(PullRequest))
        review = T.let(review || pull&.pending_review_for(user: author), T.nilable(PullRequestReview))

        # We swapped `path` to be optional with the addition of the new positional data. This validation ensures that
        # it is still required if none of the new positioning fields are used.
        if path.blank? && (file_positioning.nil? && line_positioning.nil? && multiline_positioning.nil?)
          raise Errors::Validation, "path required"
        end

        repository = T.let(pull&.head_repository, T.nilable(Repository))

        if !review && !pull
          raise Errors::Validation, "Review or Pull Request required."
        end

        if !line && subject_type == "line"
          raise Errors::Validation, "Line required for for line-level threads"
        end


        if repository&.feature_flag_enabled?(:graphql_cotd_creation, default: false)
          # These validations should probably be higher... not sure why the original implementation allows for soo many nulls :thinking_face:
          unless pull && review && repository
            raise Errors::Validation, "Pull, Review, and Repository are required."
          end

          positioning = if file_positioning
            file_positioning.to_h.merge(type: "file")
          elsif line_positioning
            line_positioning.to_h.merge(type: "line")
          elsif multiline_positioning
            multiline_positioning.to_h.merge(type: "multiline")
          end

          result = PullRequests::ReviewComments::Create.create_from_parameters(
            pull_request: pull,
            repository:,
            review:,
            review_event: submit_review ? :comment : nil,
            body:,
            actor: author,
            destination_base_commit_oid: pull.base_sha, # pro-active reposition/retarget to these, (simulate pr sync)
            destination_head_commit_oid: pull.head_sha, # pro-active reposition/retarget to these (simulate pr sync)
            only_changed_files: repository.feature_flag_enabled?(:cotd_comment_only_on_changed_files, default: false),
            parameters: {
              # New positional format.
              positioning:,

              # Previous blob positioning.
              side:,
              start_line:,
              start_side:,
              subject_type:,
              line:,
              path:,
              source_base_commit_oid: diff_range[:start_commit_oid],
              source_head_commit_oid: diff_range[:end_commit_oid],
            }.compact
          )

          case result
          when PullRequests::ReviewComments::Create::Success
            thread = result.thread
            { thread:, errors: [], pull_request_thread: Platform::Models::PullRequestThread.new(thread) }
          when PullRequests::ReviewComments::Create::Error
            errors = cotd_mapped_client_errors(result)
            { thread: nil, pull_request_thread: nil, errors: }
          else
            T.absurd(result)
          end
        else
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

      # Map COTD error attributes to GraphQL input paths.
      # This is used to translate errors from the PullRequests::ReviewComments::Create service
      # and mimic the error format from the old implementation.
      COTD_ERROR_ATTRIBUTES_TO_GRAPHQL_INPUT_PATHS = T.let({
        review: %w[input pullRequestReviewId],
        diff_entry: %w[input path],
        base_commit_oid: %w[input diffRange baseCommitOid],
        head_commit_oid: %w[input diffRange endCommitOid],
        source_base_commit_oid: %w[input diffRange startCommitOid],
        source_head_commit_oid: %w[input diffRange endCommitOid],
        start_position: %w[input startLine],
        path: %w[input path],
        line: %w[input line],
        body: %w[input body]
      }.freeze, T::Hash[Symbol, T::Array[String]])

      sig { params(result: PullRequests::ReviewComments::Create::Error).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      def cotd_mapped_client_errors(result)
        result.errors.map do |err|
          # if the result has an attribute that matches a key in the COTD_TO_GRAPHQL_ATTRIBUTES, replace the error with
          # the corresponding GraphQL input path, otherwise, use a generic "unknown" path.
          path = COTD_ERROR_ATTRIBUTES_TO_GRAPHQL_INPUT_PATHS[err.attribute.to_sym]
          attribute = T.let(path&.last&.underscore || err.attribute.to_s, String) # fallback to the original attribute if we can't map it

          {
            path: path.presence || ["unknown"],
            message: "#{attribute.titleize.downcase.capitalize} #{err.message}",
            attribute:,
            short_message: err.message
          }
        end
      end
    end
  end
end
