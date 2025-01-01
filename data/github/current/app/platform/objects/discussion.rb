# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Discussion < Platform::Objects::Base
      description "A discussion in a repository."
      scopeless_tokens_as_minimum

      implements Interfaces::Closable
      implements Interfaces::Comment
      implements Interfaces::Updatable
      implements Interfaces::Deletable
      implements Interfaces::Labelable
      implements Interfaces::Lockable
      implements Interfaces::RepositoryNode
      implements Interfaces::Subscribable
      implements Interfaces::AbuseReportable
      implements Interfaces::OrgBlockable
      implements Interfaces::Reactable
      implements Interfaces::Votable
      implements Interfaces::PerformableViaApp
      implements Interfaces::MentionSuggestable
      implements Interfaces::MarkdownPreviewable
      implements Interfaces::CopilotSummarizable

      database_id_field

      implements_node templates: [[:rd, :repo_id, :discussion_id]], as: "D", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |discussion|
        {
          prefix: :rd,
          repo_id: discussion.repository_id,
          discussion_id: discussion.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, discussion)
        permission.async_repo_and_org_owner(discussion).then do |repo, org|
          permission.access_allowed?(
            :show_discussion,
            resource: discussion,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            # Allow discussions on public repos to be returned even when the current GitHub app isn't installed on
            # the repo.
            approved_integration_required: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, discussion)
        # For GitHub Apps, we'll rely on `async_api_can_access?` to gate
        # permission to view a Discussion, as long as the app has access
        # to the repository the Discussion is in. We have to do this to make
        # sure we return the correct errors for an App that doesn't have the
        # correct permissions. See https://github.com/github/discussions/issues/1567.
        if permission.viewer&.can_have_granular_permissions?
          permission.belongs_to_repository(discussion)
        else
          discussion.async_readable_by?(permission.viewer)
        end
      end

      url_fields description: "The URL for this discussion." do |discussion|
        discussion.async_path_uri
      end

      field :number, Integer, "The number identifying this discussion within the repository.",
        null: false
      field :title, String, "The title of this discussion.", null: false
      field :body, String, description: "The main text of the discussion post.", null: false
      field :answer, Objects::DiscussionComment,
        description: "The comment chosen as this discussion's answer, if any.", null: true,
        method: :async_active_chosen_comment
      field :category, Objects::DiscussionCategory,
        description: "The category for this discussion.", null: false,
        method: :async_category

      created_at_field
      updated_at_field

      field(:comments, Connections.define(Objects::DiscussionComment),
        "The replies to the discussion.", null: false
      ) do
        argument :order_by, Inputs::DiscussionCommentOrder,
          "Ordering options for discussion comments returned from the connection.", required: false,
          default_value: { field: "created_at", direction: "ASC" }
      end

      def comments(order_by: nil)
        scope = @object.comments.filter_spam_for(@context[:viewer]).top_level

        if order_by
          field = order_by[:field]
          direction = order_by[:direction]
          scope = scope.reorder("discussion_comments.#{field} #{direction}")
        end

        scope
      end

      field :comment,
        Objects::DiscussionComment,
        description: "Get a comment from a url",
        null: true,
        mobile_only: true,
        required_capabilities: [:access_graphql_discussion_comment_url] do
        argument :url, String, "The url to decode.", required: false
      end

      def comment(url: "")
        return nil unless url.present?
        anchor = url.partition("#").last
        name, id = anchor.split("-", 2)

        return unless name&.include?("discussioncomment")

        @object.comments.find_by(id: id.to_i)
      end

      field :answer_chosen_by, Interfaces::Actor, null: true,
        description: "The user who chose this discussion's answer, if answered.",
        method: :async_chosen_comment_selected_by_user

      field :answer_chosen_at, Platform::Scalars::DateTime, null: true,
        description: "The time when a user chose this discussion's answer, if answered.",
        method: :async_chosen_comment_selected_at

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
        argument :render_mobile_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks using Mobile-specific HTML", required: false, default_value: false, mobile_only: true, required_capabilities: [:mobile_body_markup]
      end

      def body_html(
        hide_code_blobs: false,
        render_suggested_changes_as_text: false,
        scrub_video: nil,
        unfurl_references: false,
        include_suggested_changes_id: false,
        render_mobile_tasklist_blocks: false
      )
        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if T.unsafe(self).body.empty?

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
              scrub_video: scrub_video,
              render_mobile_tasklist_blocks: render_mobile_tasklist_blocks,
            }

            @object.async_body_html(context: context).then do |body_html|
              body_html || GitHub::HTMLSafeString::EMPTY
            end
          end
        end
      end

      field :formatted_body, String, description: "Formatted body when creating an issue from discussion", method: :async_formatted_body, visibility: :internal, null: true

      field :release, Objects::Release, method: :async_release, description: "The linked release for this discussion", mobile_only: true, null: true

      field :poll,
        Objects::DiscussionPoll,
        description: "The poll associated with this discussion, if one exists.",
        method: :async_poll,
        null: true

      field :updates_channel, String, "Channel value for subscribing to live updates.", null: true, mobile_only: true, required_capabilities: [:subscribe_alive_events] do
        argument :name, Enums::DiscussionPubSubTopic, "The name of the channel to use.", required: false, default_value: "updated"
      end

      def updates_channel(**arguments)
        case arguments[:name]
        when "updated"
          GitHub::WebSocket::Channels.signed_discussion(@object)
        when "timeline"
          GitHub::WebSocket::Channels.signed_discussion_timeline(@object)
        end
      end

      field :state_reason,
        Enums::DiscussionStateReason,
        description: "Identifies the reason for the discussion's state.",
        null: true

      field :isAnswered, Boolean, null: true,
        description: "Only return answered/unanswered discussions",
        method: :answered?

      # Interfaces::Comment

      sig { returns T::Boolean }
      def created_via_email
        false
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
