# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestReviewThread < Platform::Objects::Base
      description "A threaded list of comments for a given pull request."

      SENTINEL_POSITION_VALUE = 1

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, prr_thread)
        permission.load_pull_and_issue(prr_thread).then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            pull.repository = repo # avoid association load down the line
            permission.access_allowed?(:list_pull_request_comments, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_pull_request.then do |pull_request|
          permission.typed_can_see?("PullRequest", pull_request).then do |can_read_pull_request|
            can_read_pull_request && object.async_hide_from_user?(permission.viewer).then do |hide_from_viewer|
              !hide_from_viewer
            end
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rprrt, :repo_id, :pull_request_review_thread_id]], as: "PRRT", ready_date:  Platform::Helpers::GlobalId::COHORT_3 do |pull_request_review_thread|
        promise =
        if pull_request_review_thread.is_a?(::DeprecatedPullRequestReviewThread)
          pull_request_review_thread.repository
        else
          pull_request_review_thread.async_repository
        end
        promise.then do |repo|
          {
            prefix: :rprrt,
            repo_id: repo.id,
            pull_request_review_thread_id: pull_request_review_thread.id
          }
        end
      end

      database_id_field(visibility: :internal)

      url_fields(
        prefix: :discussion_diff,
        visibility: :internal,
        description: "The HTTP URL permalink for this review thread's diff excerpt on the discussion page.",
      ) do |thread|
        thread.async_discussion_diff_path_uri
      end

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :original_diff_resource_path, Scalars::URI, visibility: :internal, method: :async_original_diff_path_uri, description: "The HTTP URL permalink for this review thread positioned in the original diff.", null: true

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :current_diff_resource_path, Scalars::URI, visibility: :internal, method: :async_current_diff_path_uri, description: "The HTTP URL permalink for this review thread positioned in the current diff.", null: true

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :original_diff_file_resource_path, Scalars::URI, visibility: :internal, method: :async_original_diff_file_path_uri, description: "The HTTP URL permalink for this review thread's file in the original diff.", null: true

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :current_diff_file_resource_path, Scalars::URI, visibility: :internal, method: :async_current_diff_file_path_uri, description: "The HTTP URL permalink for this review thread's file in the current diff.", null: true

      field :pull_request, Objects::PullRequest, "Identifies the pull request associated with this thread.", method: :async_pull_request, null: false
      field :repository, Repository, "Identifies the repository associated with this thread.", method: :async_repository, null: false

      field :position, Integer, visibility: :internal, description: "Identifies the position of this thread.", method: :original_position, null: true

      field :path, String, description: "Identifies the file path of this thread.", null: false

      field :positioning, Unions::CommentPosition, null: false, description: "positioning attribute for the review thread", feature_flag: :graphql_pr_comment_positioning

      def positioning
        Loaders::PullRequest::CommentPositions.load(object.pull_request, object).then do |position|
          { positionable: object, position: }
        end
      end

      field :start_line, Integer, description: "The start line in the file to which this thread refers (multi-line only)", null: true
      def start_line
        @object.async_start_line.then do |line|
          line.current if line
        end
      end

      field :original_start_line, Integer, description: "The original start line in the file to which this thread refers (multi-line only).", method: :async_original_start_line, null: true

      field :start_line_type, String, required_capabilities: [:mobile_only_schema_mask], description: "The type of line the thread starts on (multi-line only)", null: true
      def start_line_type
        @object.async_start_line.then do |line|
          next nil unless line
          case line.type
          when :addition then "+"
          when :deletion then "-"
          else
            ""
          end
        end
      end

      field :start_diff_side, Enums::DiffSide, description: "The side of the diff that the first line of the thread starts on (multi-line only)", method: :start_side, null: true

      field :line, Integer, description: "The line in the file to which this thread refers", null: true

      def line
        if @object.on_file?
          SENTINEL_POSITION_VALUE
        else
          @object.async_safe_line
        end
      end

      field :original_line, Integer, description: "The original line in the file to which this thread refers.", null: true

      def original_line
        if @object.on_file?
          SENTINEL_POSITION_VALUE
        else
          @object.async_original_line
        end
      end

      field :end_line_type, String, required_capabilities: [:mobile_only_schema_mask], description: "The type of line the thread refers to (multi-line only)", null: true
      def end_line_type
        @object.async_end_line.then do |line|
          next nil unless line
          case line.type
          when :addition then "+"
          when :deletion then "-"
          else
            ""
          end
        end
      end

      field :diff_side, Enums::DiffSide, description: "The side of the diff on which this thread was placed.", method: :async_diff_side, null: false

      field :pull_request_commit, Objects::PullRequestCommit, visibility: :under_development, method: :async_pull_request_commit, description: "The commit to which this thread refers.", null: false

      field :is_outdated, Boolean, method: :outdated?, description: "Indicates whether this thread was outdated by newer changes.", null: false

      field :comments, resolver: Resolvers::PullRequestReviewComments, description: "A list of pull request comments associated with the thread.", connection: true do
        argument :skip, Integer, description: "Skips the first _n_ elements in the list.", required: false

        argument :focus, ID, description: "ID of element to focus on.", visibility: :internal, required: false

        argument :skip_if_collapsed, Boolean, default_value: false, description: "Skip loading of comments if thread is collapsed.", visibility: :internal, required: false
      end

      field :viewer_can_reply, Boolean, description: "Indicates whether the current viewer can reply to this thread.", null: false

      def viewer_can_reply
        @object.async_viewer_can_reply?(@context[:viewer])
      end

      field :viewer_cannot_reply_reasons, [Enums::ThreadCannotReplyReason], visibility: :internal, description: "Reasons why the current viewer can not reply to this thread.", null: false

      def viewer_cannot_reply_reasons
        @object.async_viewer_cannot_reply_reasons(@context[:viewer])
      end

      field :is_resolved, Boolean, null: false, method: :resolved?, description: "Whether this thread has been resolved"

      field :resolved_by, Objects::User, null: true, description: "The user who resolved this thread"
      def resolved_by
        @object.async_resolver.then do |resolver|
          next if resolver&.hide_from_user?(context[:viewer])

          resolver
        end
      end

      field :resolved_by_actor, Interfaces::Actor, visibility: :internal, description: "The actor who resolved this thread.", null: true
      def resolved_by_actor
        resolved_by
      end

      field :is_collapsed, Boolean, null: false, method: :resolved?, description: "Whether or not the thread has been collapsed (resolved)"

      field :viewer_can_resolve, Boolean, null: false, description: "Whether or not the viewer can resolve this thread"
      def viewer_can_resolve
        @object.async_can_resolve(context[:viewer])
      end

      field :viewer_can_unresolve, Boolean, null: false, description: "Whether or not the viewer can unresolve this thread"
      def viewer_can_unresolve
        @object.async_can_unresolve(context[:viewer])
      end

      url_fields prefix: :resolve, visibility: :internal, description: "URL for resolve form" do |thread|
        thread.async_pull_request.then do |pull_request|
          pull_request.async_path_uri.then do |uri|
            uri = uri.dup
            uri.path = "#{uri.path}/threads/#{thread.global_relay_id}/resolve"
            uri
          end
        end
      end

      url_fields prefix: :unresolve, visibility: :internal, description: "URL for unresolve form" do |thread|
        thread.async_pull_request.then do |pull_request|
          pull_request.async_path_uri.then do |uri|
            uri = uri.dup
            uri.path = "#{uri.path}/threads/#{thread.global_relay_id}/unresolve"
            uri
          end
        end
      end

      field :diff_lines, [Objects::DiffLine, null: true], required_capabilities: [:mobile_only_schema_mask], description: "The diff lines where this thread was created on.", null: true do
        # NOTE: syntax_highlighting_enabled is unused and will be removed soon - it's only here to ensure backwards compatibility with the mobile app until their queries have been updated.
        argument :syntax_highlighting_enabled, Boolean, default_value: true, description: "Indicates whether diff lines should be syntax highlighted.", required: false

        argument :max_context_lines, Integer, default_value: 3, description: "Number of context lines to return.", required: false
        argument :skip_if_collapsed, Boolean, default_value: false, description: "Skip loading of diff lines if thread is collapsed.", required: false
      end

      def diff_lines(**arguments)
        if @object.resolved? && arguments[:skip_if_collapsed]
          Promise.resolve(nil)
        elsif @object.on_file?
          @object.async_file_level_diff_lines \
            max_context_lines: arguments[:max_context_lines]
        else
          @object.async_diff_lines \
            max_context_lines: arguments[:max_context_lines]
        end
      end

      field :are_diff_lines_truncated, Boolean, description: "Are the diff lines for this thread truncated? Only true for multi-line comments that reference more than 100 lines.", null: false, method: :diff_lines_truncated?, visibility: :under_development
      field :subject_type, Enums::PullRequestReviewThreadSubjectType, description: "The level at which the comments in the corresponding thread are targeted, can be a diff line or a file", null: false

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        unless prefix == :rprrt
          raise(Platform::Errors::Internal, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        Loaders::ActiveRecord.load(::PullRequestReviewThread, parsed_id.parts[:pull_request_review_thread_id].to_i)
      end

      def self.load_from_global_id(id)
        id, version = id.split(":", 2)

        if version == ::PullRequestReviewThread::GLOBAL_ID_V2_IDENTIFIER
          # New global id format - id is based on the `id` column of `::PullRequestReviewThread`
          Loaders::ActiveRecord.load(::PullRequestReviewThread, id.to_i)
        else
          # Old global id format - id is based on the `id` column of `::PullRequestReviewComment`

          # Support for old format can be dropped once this counter stays at 0
          GitHub.dogstats.increment("platform.deprecation.pull_request_review_thread_global_id")

          Loaders::ActiveRecord.load(::PullRequestReviewComment, id.to_i).then do |review_comment|
            next nil unless review_comment

            review_comment.async_pull_request_review_thread
          end
        end
      end
    end
  end
end
