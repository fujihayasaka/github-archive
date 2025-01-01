# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueComment < Platform::Objects::Base
      description "Represents a comment on an Issue."

      implements_node templates: [[:ric, :repo_id, :issue_comment_id]], as: "IC", ready_date: "2021-07-16" do |issue_comment|
        Timeline::Placeholder
          .async_value_for(issue_comment)
          .then do |issue_comment|
            {
              prefix: :ric,
              repo_id: issue_comment.repository_id,
              issue_comment_id: issue_comment.id
            }
          end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, issue_comment)
        issue_comment.async_issue.then do |issue|
          next false if issue.nil?
          issue.async_pull_request.then do |pull_request|
            permission.async_repo_and_org_owner(issue_comment).then do |repo, org|
              access_type = pull_request.present? ? :get_pull_request_comment : :get_issue_comment
              permission.access_allowed?(access_type, repo: repo, resource: issue_comment, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_issue.then do |issue|
          next false if issue.nil?
          issue.async_pull_request.then do |pull_request|
            if pull_request.present?
              next permission.belongs_to_pull_request(object, pull_request)
            else
              next permission.belongs_to_issue(object)
            end
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Minimizable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::PerformableViaApp
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::OrgBlockable
      implements Interfaces::AbuseReportable
      implements Interfaces::RepositoryNode
      implements Interfaces::Trigger
      implements Interfaces::SafeUser

      full_database_id_field

      url_fields description: "The HTTP URL for this issue comment" do |issue_comment|
        issue_comment.async_path_uri
      end

      field :body_version, String, visibility: :internal, description: "Identifies the comment body hash.", null: false

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

      field :issue, Objects::Issue, method: :async_issue, description: "Identifies the issue associated with the comment.", null: false

      field :pull_request, Objects::PullRequest, description: <<~DESCRIPTION, null: true do
          Returns the pull request associated with the comment, if this comment was made on a
          pull request.
        DESCRIPTION
      end

      def pull_request
        @object.async_issue.then(&:async_pull_request)
      end

      field :author_to_repo_owner_sponsorship, Objects::Sponsorship, visibility: {
        internal: { environments: [:enterprise] },
        under_development: { environments: [:dotcom] },
      }, description: "The sponsorship from the comment author to the repo owner.", null: true

      def author_to_repo_owner_sponsorship
        return unless GitHub.sponsors_enabled?

        @object.async_author_to_repo_owner_sponsorship(@context[:viewer])
      end

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false do
        argument :channel, Enums::IssuePubSubTopic, "The channel to use.", required: true
      end

      def websocket(channel:)
        case channel
        when "updated"
          GitHub::WebSocket::Channels.issue(@object)
        end
      end
    end
  end
end
