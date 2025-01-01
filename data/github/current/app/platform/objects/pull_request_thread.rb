# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestThread < Platform::Objects::Base
      description "A threaded list of comments for a given pull request."

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
      #  Platform::Helpers::GlobalId::COHORT_3
      implements_node templates: [[:rprt, :repo_id, :pull_request_thread_id]], as: "PRT", ready_date: "2022-08-15" do |pull_request_review_thread|
        promise =
        if pull_request_review_thread.is_a?(::DeprecatedPullRequestReviewThread)
          pull_request_review_thread.repository
        else
          pull_request_review_thread.async_repository
        end
        promise.then do |repo|
          {
            prefix: :rprt,
            repo_id: repo.id,
            pull_request_thread_id: pull_request_review_thread.id
          }
        end
      end

      DeprecationNotice = {
        start_date: Date.new(2024, 3, 1),
        reason: "`databaseId` will be removed.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "JanKoszewski",
      }

      database_id_field(visibility: :internal, deprecated: DeprecationNotice)
      full_database_id_field(visibility: :internal)

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

      field :subject, Unions::PullRequestThreadSubject, description: "The relation of this thread to the pull request.", null: false
      def subject
        Models::PullRequestDiffThread.new(@object.review_thread)
      end

      field :is_outdated, Boolean, description: "Indicates whether this thread was outdated by newer changes.", method: :outdated?, null: false

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

      field :start_line, Integer, description: "The line of the first file diff in the thread.", null: true
      def start_line
        @object.async_start_line.then do |line|
          line.current if line
        end
      end

      field :start_diff_side, Enums::DiffSide, description: "The side of the diff that the first line of the thread starts on (multi-line only)", method: :async_start_side, null: true
      def async_start_side
        @object.async_start_side.then do |side|
          side
        end
      end

      field :line, Integer, description: "The line in the file to which this thread refers", null: true, method: :async_line
      def async_line
        @object.async_adjusted_blob_position.then do |line|
          line + 1 if line && !@object.outdated?
        end
      end

      field :diff_side, Enums::DiffSide, description: "The side of the diff on which this thread was placed.", method: :async_diff_side, null: false
      def async_diff_side
        @object.async_position_data.then(&:diff_side)
      end

      field :path, String, description: "Identifies the file path of this thread.", null: false

      field :path_digest, String, "The hashed path of the thread's changed file", null: false, visibility: :internal
      def path_digest
        @object.path_digest
      end

      field :subject_type, Enums::PullRequestReviewThreadSubjectType, description: "The level at which the comments in the corresponding thread are targeted, can be a diff line or a file", null: false

      class ReviewCommentRepoMismatch < StandardError
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        unless prefix == :rprt
          raise(Platform::Errors::Internal, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        id = parsed_id.parts[:pull_request_thread_id]
        Loaders::ActiveRecord.load(::PullRequestReviewThread, id.to_i).then do |loaded_thread|
          if loaded_thread.nil?
            # Old global id format - id is based on the `id` column of `::PullRequestReviewComment`

            # Support for old format can be dropped once this counter stays at 0
            GitHub.dogstats.increment("platform.deprecation.pull_request_review_thread_global_id")
            Loaders::ActiveRecord.load(::PullRequestReviewComment, id.to_i).then do |review_comment|
              next nil unless review_comment

              if review_comment.repository_id != parsed_id.parts[:repo_id]
                error = ReviewCommentRepoMismatch.new("review comment repo doesn't match parsed repo")
                error.set_backtrace(caller)
                Failbot.report(error,
                  "gh.pull_request_review_thread.guid": parsed_id.parts,
                  "gh.repo.id": review_comment.repository_id
                )

                next nil
              end

              review_comment.async_pull_request_review_thread.then do |thread|
                Platform::Models::PullRequestThread.new(thread)
              end
            end
          else
            Platform::Models::PullRequestThread.new(loaded_thread)
          end
        end
      end

      def self.load_from_global_id(id)
        id, version = id.split(":", 2)

        if version == ::PullRequestReviewThread::GLOBAL_ID_V2_IDENTIFIER
          # New global id format - id is based on the `id` column of `::PullRequestReviewThread`
          Loaders::ActiveRecord.load(::PullRequestReviewThread, id.to_i).then do |thread|
            Platform::Models::PullRequestThread.new(thread)
          end
        else
          # Old global id format - id is based on the `id` column of `::PullRequestReviewComment`

          # Support for old format can be dropped once this counter stays at 0
          GitHub.dogstats.increment("platform.deprecation.pull_request_review_thread_global_id")

          Loaders::ActiveRecord.load(::PullRequestReviewComment, id.to_i).then do |review_comment|
            next nil unless review_comment

            review_comment.async_pull_request_review_thread.then do |thread|
              Platform::Models::PullRequestThread.new(thread)
            end
          end
        end
      end
    end
  end
end
