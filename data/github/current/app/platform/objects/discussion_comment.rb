# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DiscussionComment < Platform::Objects::Base
      description "A comment on a discussion."
      scopeless_tokens_as_minimum

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Minimizable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::AbuseReportable
      implements Interfaces::OrgBlockable
      implements Interfaces::Reactable
      implements Interfaces::Votable
      implements Interfaces::PerformableViaApp

      implements_node templates: [[:rdc, :repo_id, :discussion_comment_id]], as: "DC", ready_date: "2021-08-30" do |discussion_comment|
        {
          prefix: :rdc,
          repo_id: discussion_comment.repository_id,
          discussion_comment_id: discussion_comment.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, comment)
        comment.async_discussion.then do |_discussion|
          permission.async_repo_and_org_owner(comment).then do |repo, org|
            permission.access_allowed?(
              :show_discussion,
              resource: comment,
              current_org: org,
              repo: repo,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              # Allow discussion comments on public repos to be returned even when the current GitHub app isn't
              # installed on the repo.
              approved_integration_required: false,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, comment)
        comment.async_readable_by?(permission.viewer)
      end

      database_id_field

      url_fields description: "The URL for this discussion comment." do |comment|
        comment.async_path_uri
      end

      field :discussion, Platform::Objects::Discussion, description: "The discussion this comment was created in",
        null: true, method: :async_discussion

      field :replyTo, Platform::Objects::DiscussionComment, description: "The discussion comment this comment is a reply to",
        null: true, method: :async_parent_comment

      field(:replies, Connections.define(Objects::DiscussionComment),
        "The threaded replies to this comment.", null: false
      ) do
        argument :order_by, Inputs::DiscussionCommentOrder,
          "Ordering options for threaded discussion comments returned from the connection.",
          required: false,
          default_value: { field: "created_at", direction: "ASC" }
      end

      def replies(order_by: nil)
        scope = @object.comments.filter_spam_for(@context[:viewer])

        if order_by
          field = order_by[:field]
          direction = order_by[:direction]
          scope = scope.reorder("discussion_comments.#{field} #{direction}")
        end

        scope
      end

      field :is_answer, Boolean, description: "Has this comment been chosen as the answer of its discussion?", null: false, method: :async_answer?

      # Note: This field resolver overrides the definition provided in Interfaces::Comment to add support
      # for these arguments. This logic is duplicated across several GraphQL objects:
      # - Discussion, DiscussionComment, Issue, IssueComment, PullRequest, PullRequestReview, and PullRequestReviewComment
      #
      # Please ensure that your changes are reflected in all of the relevant resolvers.
      field :body_html, Scalars::HTML, description: "The body rendered to HTML.", null: false do
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blocks", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, required_capabilities: [:mobile_only_schema_mask]
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
      end

      def body_html(hide_code_blobs: false, render_suggested_changes_as_text: false, scrub_video: nil, unfurl_references: false, include_suggested_changes_id: false)
        if Apps::Privileged.capable?(:video_scrubbable, app: context[:oauth_app]) && scrub_video.nil?
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

      field :viewer_can_mark_as_answer, Boolean, description: "Can the current user mark this comment as an answer?", null: false

      sig { returns Promise[T::Boolean] }
      def viewer_can_mark_as_answer
        @object.async_can_mark_as_answer?(@context[:viewer])
      end

      field :viewer_can_unmark_as_answer, Boolean, description: "Can the current user unmark this comment as an answer?", null: false

      sig { returns Promise[T::Boolean] }
      def viewer_can_unmark_as_answer
        @object.async_can_unmark_as_answer?(@context[:viewer])
      end

      field :deleted_at, Platform::Scalars::DateTime, description: "The time when this replied-to comment was deleted", null: true

      # Interfaces::Comment

      sig { returns Promise[T::Boolean] }
      def authored_by_subject_author
        @object.async_discussion.then do |discussion|
          discussion.user_id == @object.user_id
        end
      end

      sig { returns String }
      def subject_type
        "discussion"
      end

      # Interfaces::Reactable

      def reaction_groups
        @object.async_reaction_groups
      end

      sig { returns Promise[T::Boolean] }
      def viewer_can_react
        @object.async_reactable_by?(@context[:viewer])
      end
    end
  end
end
