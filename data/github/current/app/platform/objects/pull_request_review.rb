# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestReview < Platform::Objects::Base
      description "A review object for a given pull request."

      implements_node templates: [[:rprr, :repo_id, :pull_request_review_id]], as: "PRR", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |pull_request_review|
        Timeline::Placeholder.async_value_for(pull_request_review).then do |pull_request_review|
          pull_request_review.async_repository.then do |repo|
            {
              prefix: :rprr,
              repo_id: repo.id,
              pull_request_review_id: pull_request_review.id
            }
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, prr)
        permission.load_pull_and_issue(prr).then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:list_pull_request_comments, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return false if object.state == ::PullRequestReview.state_value(:pending) && object.user_id != permission.viewer.try(:id)
        object.async_user.then do |user|
          if user && user.hide_from_user?(permission.viewer)
            false
          else
            object.async_pull_request.then do |pull_request|
              Promise.all([
                permission.typed_can_see?("PullRequest", pull_request),
                object.async_readable_by?(permission.viewer),
              ]).then(&:all?)
            end
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::OrgBlockable
      implements Interfaces::AbuseReportable
      implements Interfaces::RepositoryNode
      implements Interfaces::Minimizable

      DeprecationNotice = {
        start_date: Date.new(2024, 3, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "JanKoszewski",
      }

      database_id_field(deprecated: DeprecationNotice)
      full_database_id_field

      url_fields description: "The HTTP URL permalink for this PullRequestReview." do |review|
        review.async_path_uri
      end

      url_fields prefix: :diff, visibility: :internal, description: "The HTTP URL permalink for the pull request diff of the review." do |review|
        review.async_diff_uri
      end

      field :author_can_push_to_repository, Boolean, method: :async_author_can_push_to_repository?, description: "Indicates whether the author of this review has push access to the repository.", null: false

      field :body, String, description: "Identifies the pull request review body.", null: false

      def body
        @object.body || ""
      end

      field :body_version, String, visibility: :internal, description: "Identifies the pull request review body hash.", null: false

      field :body_text, String, description: "The body of this review rendered as plain text.", null: false

      def body_text
        Promise.all([
          @object.async_repository.then do |repository|
            repository.async_owner
          end,
          @object.async_latest_user_content_edit.then do |user_content_edit|
            user_content_edit&.async_editor
          end,
        ]).then do
          @object.async_body_text.then do |body_text|
            body_text || GitHub::HTMLSafeString::EMPTY
          end
        end
      end

      # Note: This field resolver overrides the definition provided in Interfaces::Comment to add support
      # for these arguments. This logic is duplicated across several GraphQL objects:
      # - Discussion, DiscussionComment, Issue, IssueComment, PullRequest, PullRequestReview, and PullRequestReviewComment
      #
      # Please ensure that your changes are reflected in all of the relevant resolvers.
      field :body_html, Scalars::HTML, description: "The body rendered to HTML.", null: false do
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blobs", required: false, default_value: false, mobile_only: true
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, mobile_only: true
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, mobile_only: true
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, mobile_only: true
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, mobile_only: true
      end

      def body_html(hide_code_blobs: false, render_suggested_changes_as_text: false, scrub_video: nil, unfurl_references: false, include_suggested_changes_id: false)
        if Apps::Internal.capable?(:video_scrubbable, app: context[:oauth_app]) && scrub_video.nil?
          scrub_video = true
        end

        @object.async_repository.then do |repo|
          Promise.all([repo.async_owner, repo.async_network]).then do
            context = {
              viewer: @context[:viewer],
              cap_filter: @context[:cap_filter],
              unfurl_references: unfurl_references,
              hide_code_blobs: hide_code_blobs,
              scrub_video: scrub_video
            }


            @object.async_body_html(context: context).then do |body_html|
              body_html || GitHub::HTMLSafeString::EMPTY
            end
          end
        end
      end

      field :pull_request, Objects::PullRequest, method: :async_pull_request, description: "Identifies the pull request associated with this pull request review.", null: false

      field :commit, Objects::Commit, description: "Identifies the commit associated with this pull request review.", null: true

      def commit
        @object.async_pull_request.then do |pull_request|
          pull_request.async_load_pull_request_commit(@object.head_sha).then do |pull_request_commit|
            pull_request_commit&.commit
          end
        end
      end

      field :state, Enums::PullRequestReviewState, description: "Identifies the current state of the pull request review.", null: false

      def state
        ::PullRequestReview.state_name(@object.state).to_s
      end

      field :dismissed_review_state, Enums::PullRequestReviewState, description: "The state of the review before it was dismissed.", visibility: :internal, null: true

      def dismissed_review_state
        @object.async_batch_dismissed_review_state.then do |state|
          state ? ::PullRequestReview.state_name(state).to_s : nil
        end
      end

      field :comments, resolver: Resolvers::PullRequestReviewComments, numeric_pagination_enabled: true, description: "A list of review comments for the current pull request review.", connection: true

      field :on_behalf_of, Connections.define(Objects::Team), description: "A list of teams that this review was made on behalf of.", null: false, connection: true

      def on_behalf_of
        @object.async_on_behalf_of_visible_teams_for(@context[:viewer]).then do |teams|
          StableArrayWrapper.new(teams)
        end
      end

      field :on_behalf_of_reviewers, [Objects::OnBehalfOfReviewer], description: "A list of reviewers that this review was made on behalf of.", null: false, visibility: :internal

      def on_behalf_of_reviewers
        @object.async_on_behalf_of_visible_reviewers(@context[:viewer])
      end

      field :threads_and_replies, Connections::PullRequestReviewItem, mobile_only: true, description: "A union of review threads and comments that are replies to other review threads.", null: true, connection: true do
        # Note: This is not intended to be published.

        argument :skip, Integer, description: "Skips the first _n_ elements in the list.", required: false

        argument :focus, ID, description: "ID of element to focus on.", required: false
      end

      def threads_and_replies(**arguments)
        async_review_thread_models = @object.async_review_threads_for(@context[:viewer])

        Promise.all([
          async_review_thread_models,
          Platform::Loaders::PullRequestReviewCrossReviewReplies.load(
            @object.id,
            @context[:viewer],
          ),
        ]).then do |review_thread_models, cross_review_replies|
          StableArrayWrapper.new(review_thread_models + cross_review_replies).tap do |wrapper|
            wrapper.sort_by_proc = -> (item) {
              is_thread = item.is_a?(::PullRequestReviewThread)
              [item.created_at, is_thread ? 0 : 1, item.id]
            }
          end
        end
      end

      field :pull_request_threads_and_replies, Connections.define(Unions::PullRequestReviewCommentItem), description: "A union of threads and comments that are replies to other threads.", null: true, connection: true, visibility: :internal

      def pull_request_threads_and_replies
        async_review_thread_models = @object.async_review_threads_for(@context[:viewer])

        Promise.all([
          async_review_thread_models,
          Platform::Loaders::PullRequestReviewCrossReviewReplies.load(
            @object.id,
            @context[:viewer],
          ),
        ]).then do |review_thread_models, cross_review_replies|
          pr_threads = review_thread_models.map { |t| Platform::Models::PullRequestThread.new(t) }
          StableArrayWrapper.new(pr_threads + cross_review_replies).tap do |wrapper|
            wrapper.sort_by_proc = -> (item) {
              is_thread = item.is_a?(Platform::Models::PullRequestThread)
              [item.created_at, is_thread ? 0 : 1, item.id]
            }
          end
        end
      end

      # NOTE: This is not intended to be published as it is. The current implementation
      #   exposes threads that only contain the answer to a thread of another review.
      #   We plan to address this with future work on first-class review thread objects.
      field :threads, Connections::PullRequestReviewThread, mobile_only: true, description: "A list of review comment threads for this pull request review.", null: true do
        argument :skip, Integer, description: "Skips the first _n_ elements in the list.", required: false
      end

      def threads(skip: nil)
        @object.async_review_threads_for(@context[:viewer]).then do |review_threads|
          StableArrayWrapper.new(review_threads)
        end
      end

      field :submitted_at, Scalars::DateTime, "Identifies when the Pull Request Review was submitted", null: true

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false do
        argument :channel, Enums::PullRequestReviewPubSubTopic, "The channel to use.", required: true
      end

      def websocket(**arguments)
        case arguments[:channel]
        when "updated"
          GitHub::WebSocket::Channels.pull_request_review(@object)
        end
      end
    end
  end
end
