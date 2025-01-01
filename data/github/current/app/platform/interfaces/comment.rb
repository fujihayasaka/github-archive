# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Comment
      include Platform::Interfaces::Base
      description "Represents a comment."

      field :id, ID, description: "The Node ID of the Comment object", method: :global_relay_id, null: false

      field :authored_by_subject_author, Boolean, visibility: :internal, null: false, description: "Did the comment author also author the comment subject."
      def authored_by_subject_author
        case @object
        when ::CommitComment
          T.bind(self, Platform::Objects::CommitComment)
          commit.then do |commit|
            if commit.present?
              commit.async_authors.then { |authors| authors.map(&:id).include?(@object.user_id) }
            else
              false
            end
          end
        when ::GistComment
          @object.async_gist.then { |gist| T.must(gist).user_id == @object.user_id }
        when ::IssueComment
          @object.async_issue.then { |issue| T.must(issue).user_id == @object.user_id }
        when ::PullRequestReview, ::PullRequestReviewComment
          @object.async_pull_request.then { |pull| T.must(pull).user_id == @object.user_id }
        when ::DiscussionPostReply
          @object.async_discussion_post.then { |post| T.must(post).user_id == @object.user_id }
        else
          false
        end
      end

      field :author_to_repo_owner_sponsorship, Objects::Sponsorship,
        visibility: {
          internal: { environments: [:enterprise] },
          under_development: { environments: [:dotcom] },
        },
        null: true,
        description: "The sponsorship from the comment author to the repo owner."

      def author_to_repo_owner_sponsorship
        return unless GitHub.sponsors_enabled?
        return unless @object.user_id
        return unless @object.respond_to?(:async_repository)

        @object.async_repository.then do |repo|
          next unless repo
          repo.async_owner_sponsorship_from(@object.user_id, viewer: @context[:viewer])
        end
      end

      field :subject_id, ID, visibility: :internal, null: true, description: "The comment's subject id."

      def subject_id
        case @object
        when ::CommitComment
          T.bind(self, Platform::Objects::CommitComment)
          commit.then { |commit| commit.global_relay_id if commit.present? }
        when ::GistComment
          @object.async_gist.then { |gist| T.must(gist).global_relay_id }
        when ::IssueComment
          @object.async_issue.then { |issue| T.must(issue).global_relay_id }
        when ::PullRequestReview, ::PullRequestReviewComment
          @object.async_pull_request.then { |pull| T.must(pull).global_relay_id }
        when ::DiscussionPostReply
          @object.async_discussion_post.then { |post| T.must(post).global_relay_id }
        else
          nil
        end
      end

      field :viewer_did_author, Boolean, description: "Did the viewer author this comment.", null: false

      def viewer_did_author
        if @context[:viewer]
          @object.user_id == @context[:viewer].id
        else
          false
        end
      end

      field :body, String, description: "The body as Markdown.", null: false

      def body
        case @object
        when ::PullRequest
          @object.async_issue.then { |issue| T.must(issue).body || "" }
        else
          @object.body || ""
        end
      end

      field :body_html, Scalars::HTML, description: "The body rendered to HTML.", null: false do
        # TODO: before making these public, figure out which `bodyHTML` fields _actually_ use them.
        # Then remove them from the interface and add them to those fields only.
        # (Otherwise, add no-op arguments, which is confusing!)
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blobs", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, required_capabilities: [:mobile_only_schema_mask]
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
      end

      def body_html(**args)
        @object.async_body_html.then do |body_html|
          body_html || GitHub::HTMLSafeString::EMPTY
        end
      end

      field :short_body_html, Scalars::HTML, description: "Returns a truncated version of the body, rendered as HTML.", null: false, visibility: :under_development do
        argument :limit, Integer, "Limit the length of the returned HTML.", default_value: 150,
          required: false
      end

      def short_body_html(limit: nil)
        @object.async_truncated_body_html(limit)
      end

      field :body_text, String, description: "The body rendered to text.", null: false

      def body_text
        @object.async_body_text.then do |body_text|
          body_text || ""
        end
      end

      field :body_version, String, visibility: :internal, description: "The comment body hash.", null: false

      created_at_field
      updated_at_field

      field :published_at, Scalars::DateTime, "Identifies when the comment was published at.", method: :created_at, null: true

      field :created_via_email, Boolean, "Check if this comment was created via an email reply.", null: false

      field :viewer_can_read_user_content_edits, Boolean, visibility: :internal, description: "Check if this comment's edits may be shown to the viewer.", null: false

      def viewer_can_read_user_content_edits
        if @object.is_a?(UserContentEditable)
          @object.async_viewer_can_read_user_content_edits?(@context[:viewer])
        else
          Promise.resolve(false)
        end
      end

      field :user_content_edits, Connections::UserContentEdit, description: "A list of edits to this content.", null: true, connection: true

      def user_content_edits
        viewer_can_read_user_content_edits.then do |can_read|
          next ArrayWrapper.new unless can_read
          (@object.is_a?(PullRequest) ? @object.async_issue : Promise.resolve(@object)).then do |comment|
            comment.user_content_edits.order(id: :desc)
          end
        end
      end

      field :last_user_content_edit, Objects::UserContentEdit, description: "The last edit to this content.", null: true, visibility: :under_development

      def last_user_content_edit
        viewer_can_read_user_content_edits.then do |can_read|
          next unless can_read
          (@object.is_a?(PullRequest) ? @object.async_issue : Promise.resolve(@object)).then do |comment|
            comment.async_latest_user_content_edit
          end
        end
      end

      field :includes_created_edit, Boolean, "Check if this comment was edited and includes an edit with the creation data", null: false

      def includes_created_edit
        viewer_can_read_user_content_edits.then do |can_read|
          can_read ? @object.async_includes_created_edit? : false
        end
      end

      field :spammy, Boolean, visibility: :internal, description: "Check if this comment is spammy.", null: false

      def spammy
        @object.async_user_is_spammy(@context[:viewer])
      end

      field :author_association, Enums::CommentAuthorAssociation, description: "Author's association with the subject of the comment.", null: false

      def author_association
        association = CommentAuthorAssociation.new(comment: @object, viewer: @context[:viewer])
        association.async_to_sym
      end

      field :author, description: "The actor who authored the comment.", resolver: Resolvers::ActorUser, scope: true

      field :editor, Interfaces::Actor, description: "The actor who edited the comment.", null: true

      def editor
        viewer_can_read_user_content_edits.then do |can_read|
          next unless can_read
          ::Platform::Helpers::Editor.for(editable: @object, context: @context)
        end
      end

      field :last_edited_at, Scalars::DateTime, description: "The moment the editor made the last edit", null: true

      def last_edited_at
        last_user_content_edit.then do |user_content_edit|
          user_content_edit&.edited_at
        end
      end

      field :show_edit_history_onboarding, Boolean, description: "Should the viewer see the edit history onboarding", null: false, visibility: :internal

      def show_edit_history_onboarding
        # this field is deprecated and will be removed in the future
        false
      end

      field :stafftools_url, Platform::Scalars::URI, visibility: :internal, description: "The URL for the content in stafftools for moderation purposes", null: true

      # Returns the stafftools URL for comment types viewable in stafftools
      def stafftools_url
        return nil unless @context[:viewer].try(:site_admin?)
        return nil unless @object.respond_to?(:async_repository)

        @object.async_repository.then do |repo|
          case @object
          when IssueComment
            @object.async_issue.then do |issue|
              # nwo with suffix is allowed for stafftools URLs
              "/stafftools/repositories/#{repo.nwo}/issues/#{T.must(issue).number}/comments/#{@object.id}" # rubocop:disable GitHub/DoNotAllowNameWithOwner
            end
          when PullRequestReviewComment
            @object.async_pull_request.then do |pr|
              # nwo with suffix is allowed for stafftools URLs
              "/stafftools/repositories/#{repo.nwo}/pull_requests/#{T.must(pr).number}/review_comments/#{@object.id}" # rubocop:disable GitHub/DoNotAllowNameWithOwner
            end
          when CommitComment
            UrlHelpers.stafftools_commit_comment_path(@object)
          else
            nil
          end
        end
      end

      field :show_first_contribution_prompt, Boolean, visibility: :internal, description: "Should the viewer see the first contribution prompt", null: false

      def show_first_contribution_prompt
        if @object.is_a?(PullRequest) && @context[:viewer]
          @object.async_issue.then do |issue|
            T.must(issue).async_repository.then do |repository|
              T.must(repository).async_owner.then do
                T.must(issue).show_first_contribution_prompt?(@context[:viewer])
              end
            end
          end
        else
          false
        end
      end

      field :show_spammy_badge, Boolean, visibility: :internal, description: "Should the viewer see the spammy badge", null: false
      def show_spammy_badge
        return false unless @context[:viewer].try(:site_admin?)
        @object.async_user_is_spammy(@context[:viewer])
      end

      field :comment_type, String, visibility: :internal, description: "Type of comment", null: false, method: :comment_type

      def comment_type
        @object.class.to_s.underscore
      end
    end
  end
end
