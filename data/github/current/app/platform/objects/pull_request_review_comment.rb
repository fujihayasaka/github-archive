# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestReviewComment < Platform::Objects::Base
      description "A review comment associated with a given repository pull request."

      SENTINEL_POSITION_VALUE = 1

      implements_node templates: [[:rprrc, :repo_id, :id]], as: "PRRC", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |pull_request_review_comment|
        {
          prefix: :rprrc,
          repo_id: pull_request_review_comment.repository_id,
          id: pull_request_review_comment.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, prr_comment)
        permission.load_pull_and_issue(prr_comment).then do |pull|
          permission.async_repo_and_org_owner(prr_comment).then do |repo, org|
            pull.repository = repo # avoid association load down the line
            permission.access_allowed?(:get_pull_request_comment, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repository|
          if repository.hide_from_user?(permission.viewer)
            false
          else
            permission.belongs_to_pull_request(object) && object.visible_to?(permission.viewer)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::OrgBlockable
      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Minimizable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::AbuseReportable
      implements Interfaces::RepositoryNode

      DeprecationNotice = {
        start_date: Date.new(2024, 3, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "JanKoszewski",
      }

      database_id_field(deprecated: DeprecationNotice)
      full_database_id_field

      url_fields description: "The HTTP URL permalink for this review comment." do |pr_review_comment|
        pr_review_comment.async_path_uri
      end

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :original_diff_resource_path, Scalars::URI, visibility: :internal, method: :async_original_diff_path_uri, description: "The HTTP URL permalink for this review comment positioned in the original diff.", null: true

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for *Url.
      field :current_diff_resource_path, Scalars::URI, visibility: :internal, method: :async_current_diff_path_uri, description: "The HTTP URL permalink for this review comment positioned in the current diff.", null: true

      url_fields \
        prefix: :update,
        visibility: :internal,
        deprecated: {
          start_date: Date.new(2018, 2, 1),
          reason: "Object-specific update endpoints will be removed.",
          superseded_by: nil,
          owner: "xuorig",
        },
        description: "The HTTP URL to the endpoint for updating this review comment." do |pr_review_comment|
        pr_review_comment.async_update_path_uri
      end

      field :pull_request, Objects::PullRequest, method: :async_pull_request, description: "The pull request associated with this review comment.", null: false

      field :pull_request_review, Objects::PullRequestReview, method: :async_pull_request_review, description: "The pull request review associated with this review comment.", null: true

      field :commit_id, Scalars::GitObjectID, description: "oid of commit associated with the comment.", visibility: :internal, null: false
      field :commit, Objects::Commit, description: "Identifies the commit associated with the comment.", null: true, method: :async_commit
      field :original_commit, Objects::Commit, description: "Identifies the original commit associated with the comment.", null: true, method: :async_original_commit
      field :position, Integer, "The line index in the diff to which the comment applies.", null: true do
        deprecated(
          start_date: Date.new(2023, 4, 1),
          reason: "We are phasing out diff-relative positioning for PR comments",
          superseded_by: "Use the `line` and `startLine` fields instead, which are file line numbers instead of diff line numbers",
          owner: "aharpole",
        )
      end

      def position
        @object.async_pull_request_review_thread.then do |thread|
          if thread.on_file?
            SENTINEL_POSITION_VALUE
          else
            @object.async_position
          end
        end
      end

      field :original_position, Integer, "The original line index in the diff to which the comment applies.", null: false do
        deprecated(
          start_date: Date.new(2023, 4, 1),
          reason: "We are phasing out diff-relative positioning for PR comments",
          superseded_by: nil,
          owner: "aharpole",
        )
      end

      def original_position
        @object.async_pull_request_review_thread.then do |thread|
          if thread.on_file?
            SENTINEL_POSITION_VALUE
          else
            @object.async_original_position
          end
        end
      end

      field :body, String, "The comment body of this review comment.", null: false
      field :body_version, String, visibility: :internal, description: "The comment body hash of this review comment.", null: false
      field :diff_hunk, String, "The diff hunk to which the comment applies.", null: false

      def diff_hunk
        @object.async_pull_request_review_thread.then do |thread|
          if thread.on_file?
            ""
          else
            @object.async_diff_hunk
          end
        end
      end

      field :path, String, "The path to which the comment applies.", null: false, method: :async_path
      field :created_at, Scalars::DateTime, "Identifies when the comment was created.", null: false
      field :updated_at, Scalars::DateTime, "Identifies when the comment was last updated.", null: false

      field :published_at, Scalars::DateTime, "Identifies when the comment was published at.", method: :async_submitted_at, null: true
      field :drafted_at, Scalars::DateTime, "Identifies when the comment was created in a draft state.", method: :created_at, null: false
      field :state, Enums::PullRequestReviewCommentState, "Identifies the state of the comment.", null: false

      field :body_text, String, method: :async_body_text, description: "The comment body of this review comment rendered as plain text.", null: false

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

      def body_html(hide_code_blobs: false, render_suggested_changes_as_text: false, include_suggested_changes_id: false, scrub_video: nil, unfurl_references: false)
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
              render_suggested_changes_as_text: render_suggested_changes_as_text,
              include_suggested_changes_id: include_suggested_changes_id,
              scrub_video: scrub_video
            }

            @object.async_body_html(context: context).then do |body_html|
              body_html || GitHub::HTMLSafeString::EMPTY
            end
          end
        end
      end

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false do
        argument :channel, Enums::PullRequestPubSubTopic, "The channel to use.", required: true
      end

      def websocket(**arguments)
        case arguments[:channel]
        when "updated"
          GitHub::WebSocket::Channels.pull_request(@object)
        end
      end

      field :thread, PullRequestReviewThread, required_capabilities: [:mobile_only_schema_mask], description: "The thread this comment was posted in.", null: true

      def thread
        @object.async_pull_request_review_thread
      end

      field :pull_request_thread, PullRequestThread, visibility: :internal, description: "The thread this comment is part of.", null: true

      def pull_request_thread
        @object.async_pull_request_review_thread.then do |t|
          Platform::Models::PullRequestThread.new(t)
        end
      end

      field :reply_to, PullRequestReviewComment, description: "The comment this is a reply to.", null: true

      def reply_to
        if @object.reply?
          Loaders::ActiveRecord.load(::PullRequestReviewComment, @object.reply_to_id).then do |reply|
            reply&.visible_to?(@context[:viewer]) ? reply : nil
          end
        end
      end

      field :outdated, Boolean, method: :async_outdated, description: "Identifies when the comment body is outdated", null: false

      field :selection_contains_deletions, Boolean, visibility: :internal, method: :async_selection_contains_deletions, description: "Is this comment on a range that contains deletions", null: false
      field :subject_type, Enums::PullRequestReviewThreadSubjectType, description: "The level at which the comments in the corresponding thread are targeted, can be a diff line or a file", null: false, method: :async_subject_type

      field :line, Integer, description: "The end line number on the file to which the comment applies", null: true, method: :async_line
      field :start_line, Integer, description: "The start line number on the file to which the comment applies", null: true, method: :async_start_line_number
      field :original_line, Integer, description: "The end line number on the file to which the comment applied when it was first created", null: true, method: :async_original_line
      field :original_start_line, Integer, description: "The start line number on the file to which the comment applied when it was first created", null: true, method: :async_original_start_line


      def time_async(metric_name, tags:)
        timing_start = GitHub::Dogstats.monotonic_time
        promise = yield
        promise.then do |resolved_result|
          GitHub.dogstats.distribution_timing_since(metric_name, timing_start, tags: tags)
          resolved_result
        end
      end
    end
  end
end
