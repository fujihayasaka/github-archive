# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Issue < Platform::Objects::Base
      include IssuesHelper
      include GitHub::ResilienceMixin

      description "An Issue is a place to discuss ideas, enhancements, tasks, and bugs for a project."

      implements_node templates: [[:ri, :repo_id, :issue_id]], as: "I", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |issue|
        {
          prefix: :ri,
          repo_id: issue.repository_id,
          issue_id: issue.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, issue)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          issue.async_pull_request.then do |_pull|
            permission.access_allowed?(:show_issue,
              resource: issue,
              repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              # Allow issues on public repos to be returned even when the current GitHub app isn't installed on the repo
              approved_integration_required: false,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_pull_request.then do |pull_request|
          source = pull_request ? pull_request : object
          source.async_hide_from_user?(permission.viewer).then do |hide_from_user|
            if hide_from_user
              false
            else
              permission.load_repo_and_owner(object).then do
                object.readable_by?(permission.viewer)
              end
            end
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Assignable
      implements Interfaces::Closable
      implements Interfaces::Comment
      implements Interfaces::Commentable
      implements Interfaces::Deletable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::Labelable
      implements Interfaces::Lockable
      implements Interfaces::MentionSuggestable
      implements Interfaces::PerformableViaApp
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::RepositoryNode
      implements Interfaces::Subscribable
      implements Interfaces::SubscribableThread
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::OrgBlockable
      implements Interfaces::AbuseReportable
      implements Interfaces::Trigger
      implements Interfaces::ProjectNextOwner
      implements Interfaces::ProjectV2Owner
      implements Interfaces::MarkdownPreviewable
      implements Interfaces::SafeUser
      implements Interfaces::CopilotSummarizable

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          repository && Loaders::IssueByNumber.load(repository.id, params[:id].to_i)
        end
      end

      url_fields description: "The HTTP URL for this issue" do |issue|
        issue.async_path_uri
      end

      database_id_field
      full_database_id_field
      field :number, Integer, "Identifies the issue number.", null: false
      field :title, String, "Identifies the issue title.", null: false

      field :discussion, Discussion, description: "Identifies the discussion associated with the issue", visibility: :internal, null: true
      def discussion
        @object.async_discussion.then do |discussion|
          next nil unless discussion

          discussion.async_readable_by?(@context[:viewer]).then do |can_read|
            can_read ? discussion : nil
          end
        end
      end

      field :title_html, String, "Identifies the issue title rendered to HTML.", null: false

      def title_html
        GitHub::Goomba::TitleMarkdownFilter.call(@object.title)
      end

      field :state, Enums::IssueState, "Identifies the state of the issue.", null: false
      field :state_reason, Enums::IssueStateReason, "Identifies the reason for the issue state.", null: true do
        argument :enable_duplicate, Boolean, "Whether or not to return state reason for duplicates", required: false, default_value: false
      end

      def state_reason(enable_duplicate: false)
        if @object.state_reason
          if @object.state_reason == PlatformTypes::IssueStateReason::DUPLICATE.downcase && !enable_duplicate
            return PlatformTypes::IssueStateReason::NOT_PLANNED.downcase
          end
          @object.state_reason
        elsif @object.closed?
          PlatformTypes::IssueStateReason::COMPLETED.downcase
        end
      end

      field :duplicate_of, Issue, "A reference to the original issue that this issue has been marked as a duplicate of.", null: true, visibility: :internal
      def duplicate_of
        return Promise.resolve(nil) unless @object.state_reason&.downcase == PlatformTypes::IssueStateReason::DUPLICATE.downcase

        Platform::Loaders::DuplicateIssueFromIssue.load(@object.id).then do |duplicates|
          # use the most recent duplicate
          duplicate = duplicates&.max_by(&:updated_at)
          next nil unless duplicate
          duplicate.async_canonical_issue.then do |canonical_issue|
            next nil unless context[:cap_filter].authorized_resources([canonical_issue]).any?
            canonical_issue.async_readable_by?(@context[:viewer]).then do |can_read|
              next nil unless can_read
              canonical_issue
            end
          end
        end
      end

      field :milestone, Milestone, method: :async_milestone, description: "Identifies the milestone associated with the issue.", null: true, scope: true
      field :viewer_can_set_milestone,
        Boolean,
        visibility: :internal,
        description: "Indicates if the viewer can edit the milestone of the issue.",
        null: false
      def viewer_can_set_milestone
        @object.async_can_set_milestone?(context[:viewer])
      end

      field :body, String, description: "Identifies the body of the issue.", null: false

      def body
        @object.body || ""
      end

      field :body_version, String, visibility: :internal, description: "Identifies the issue body hash.", null: false

      field :body_text, String, description: "Identifies the body of the issue rendered to text.", null: false

      def body_text
        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if body.empty?

        @object.async_body_text.then do |body_text|
          body_text || GitHub::HTMLSafeString::EMPTY
        end
      end

      # Note: This field resolver overrides the definition provided in Interfaces::Comment to add support
      # for these arguments. This logic is duplicated across several GraphQL objects:
      # - Discussion, DiscussionComment, Issue, IssueComment, PullRequest, PullRequestReview, and PullRequestReviewComment
      #
      # Please ensure that your changes are reflected in all of the relevant resolvers.
      field :body_html, Scalars::HTML, description: "The body rendered to HTML.", null: false do
        # TODO: before making these public, figure out which `bodyHTML` fields _actually_ use them.
        # Then remove them from the interface and add them to those fields only.
        # (Otherwise, add no-op arguments, which is confusing!)
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blobs", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, required_capabilities: [:mobile_only_schema_mask]
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_mobile_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks using Mobile-specific HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask, :mobile_body_markup]
        argument :render_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks", required: false, default_value: false, visibility: :internal
      end

      def body_html(
        hide_code_blobs: false,
        render_suggested_changes_as_text: false,
        scrub_video: nil,
        unfurl_references: false,
        include_suggested_changes_id: false,
        render_mobile_tasklist_blocks: false,
        render_tasklist_blocks: false
      )
        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if body.empty?

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
              render_tasklist_blocks: render_tasklist_blocks,
            }

            @object.async_body_html(context: context).then do |body_html|
              body_html || GitHub::HTMLSafeString::EMPTY
            end
          end
        end
      end

      url_fields prefix: :body, description: "The http URL for this issue body" do |issue|
        issue.async_path_body_uri
      end

      field :closed_by, Interfaces::Actor, visibility: :internal, method: :async_closed_by, description: "The actor who closed the issue.", null: true

      field :task_list_item_count, Integer, required_capabilities: [:mobile_only_schema_mask], description: "Number of tasks in the issue's task list", null: false do
        argument :statuses, [Enums::TaskListItemStatus, null: true], "Limit the count to tasks in the specified statuses.", required: false
      end

      def task_list_item_count(**arguments)
        @object.async_task_list_item_count(*arguments[:statuses])
      end

      field :task_list_summary, Objects::TaskListSummary, null: true,
        description: "A summary of this issue's task list.", visibility: :under_development

      field :comment, Objects::IssueComment,
          description: "Find a particular comment on this issue.",
          visibility: :under_development, null: true do
        argument :database_id, Int, "Look up comment by its database ID.", required: true
      end

      def comment(database_id:)
        if context[:permission].typed_can_access?("Issue", @object)
          @object.comments.filter_spam_for(@context[:viewer]).where(id: database_id).first
        end
      end

      field :comments, resolver: Resolvers::IssueComments, description: "A list of comments associated with the Issue.", numeric_pagination_enabled: true

      field :total_comments_count, Integer,
        method: :issue_comments_count,
        null: true,
        description: "Returns a count of how many comments this issue has received.",
        required_capabilities: [:mobile_only_schema_mask]

      field :timeline,
        resolver: Platform::Resolvers::IssueTimeline,
        description: "A list of events, comments, commits, etc. associated with the issue.",
        deprecated: {
          start_date: Date.new(2020, 4, 22),
          reason: "`timeline` will be removed",
          superseded_by: "Use Issue.timelineItems instead.",
          owner: "mikesea",
        }

      # New, fully batched timeline powered by `Timeline::IssueTimeline`. We do not
      # intend to publish it with this name!
      #
      # TODO: Make the timeline paginateable and publish it by merging it into `timeline`.
      field :timeline_items,
        resolver: Platform::Resolvers::IssueTimelineItems,
        max_page_size: 250,
        scope: true,
        description: "A list of events, comments, commits, etc. associated with the issue."

      field :timeline_item, Unions::IssueTimelineItems, description: "Get a timeline item from a url", null: true, required_capabilities: [:mobile_only_schema_mask] do
        argument :url, String, "The url to decode.", required: false
      end

      def timeline_item(url: "")
        return nil unless url.present?
        anchor = url.partition("#").last
        name, id = anchor.split("-", 2)

        return unless name&.include?("issuecomment")

        @object.comments.find_by(id: id.to_i)
      end

      field :tracked_issues,
        resolver: Resolvers::TrackedIssues,
        connection: true,
        description: "A list of issues tracked inside the current issue",
        visibility: {
          public: { environments: [:dotcom] },
          under_development: { environments: [:enterprise] },
        }

      field :tasklist_blocks, Connections.define(Objects::TasklistBlock), null: true,
      description: "A list of tasklist blocks together with their items - issues and drafts",
      visibility: :internal
      def tasklist_blocks
        @object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            HierarchyCommands::Preload.async_maybe_preload(
              issue: @object,
              repository: repo,
              owner: owner,
              viewer: context[:viewer]
            ).then do
              @object.hierarchy ? ArrayWrapper.new(@object.hierarchy.tasklist_blocks&.sort_by(&:order)) : []
            end
          end
        end
      end

      field :tasklist_blocks_completion, Platform::Objects::TrackedIssueCompletion, null: true,
      description: "Completion status for tasklist blocks in this issue",
      visibility: :internal
      def tasklist_blocks_completion
        @object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            HierarchyCommands::Preload.async_maybe_preload(
              issue: @object,
              repository: repo,
              owner: owner,
              viewer: context[:viewer]
            ).then do
              @object.hierarchy ? @object.hierarchy.completion : nil
            end
          end
        end
      end

      field :tracked_in_issues,
        resolver: Resolvers::TrackedInIssues,
        connection: true,
        description: "A list of issues that track this issue",
        visibility: {
          public: { environments: [:dotcom] },
          under_development: { environments: [:enterprise] },
        }

      field :tracked_issues_count, Integer, null: false,
        description: "The number of tracked issues for this issue",
        visibility: {
          public: { environments: [:dotcom] },
          under_development: { environments: [:enterprise] },
        } do
          argument :states, [Enums::TrackedIssueStates, null: true], "Limit the count to tracked issues with the specified states.", required: false
        end

      def tracked_issues_count(states: [])
        @object.async_source_issue_links.then do |issue_links|
          next issue_links.size if states.compact.empty?

          requested_states = []
          requested_states << "open" if states.include?(:open)
          requested_states << "closed" if states.include?(:closed)

          tracked_issues_ids = issue_links.pluck(:target_issue_id).compact
          Platform::Loaders::ActiveRecord.load_all(::Issue, tracked_issues_ids).then do |tracked_issues|
            tracked_issues.count { |tracked_issue| T.must(tracked_issue).state.in?(requested_states) }
          end
        end
      end

      field :participants, resolver: Resolvers::Participants, description: "A list of Users that are participating in the Issue conversation."

      field :websocket, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: false do
        argument :channel, Enums::IssuePubSubTopic, "The channel to use.", required: true
      end

      def websocket(**arguments)
        case arguments[:channel]
        when "updated"
          GitHub::WebSocket::Channels.issue(@object)
        when "timeline"
          GitHub::WebSocket::Channels.issue_timeline(@object)
        when "state"
          GitHub::WebSocket::Channels.issue_state(@object)
        end
      end

      field :updates_channel, String, "Channel value for subscribing to live updates.", null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events] do
        argument :name, Enums::IssuePubSubTopic, "The name of the channel to use.", required: false, default_value: "updated"
      end

      field :thread_subscription_channel, String, visibility: :internal, description: "The websocket channel ID for live updates.", null: true

      def thread_subscription_channel
        return unless @context[:viewer]

        @object.async_repository.then do |repository|
          GitHub::WebSocket::Channels.signed_thread_subscription(@context[:viewer], repository, @object.id)
        end
      end

      def updates_channel(**arguments)
        case arguments[:name]
        when "updated"
          T.unsafe(GitHub::WebSocket::Channels).signed_issue(@object)
        when "timeline"
          T.unsafe(GitHub::WebSocket::Channels).signed_issue_timeline(@object)
        when "state"
          T.unsafe(GitHub::WebSocket::Channels).signed_issue_state(@object)
        when "close_references"
          T.unsafe(GitHub::WebSocket::Channels).signed_close_issue_references(@object)
        end
      end

      field :project_cards, resolver: Resolvers::ProjectCards, connection: false,  null: false, description: "List of project cards associated with this issue.", deprecated: Helpers::ProjectDeprecation::Notice

      field :project_next_items, resolver: Resolvers::ProjectNextItems,
        required_capabilities: [:mobile_only_schema_mask],
        description: "List of project items associated with this issue."

      field :project_items, resolver: Resolvers::ProjectV2Items,
        description: "List of project items associated with this issue."

      # TODO: Remove this field once we deprecate the existing project_items and replace with this nullable version
      field :project_items_next, resolver: Resolvers::ProjectV2Items,
        description: "List of project items associated with this issue.",
        visibility: :internal, null: true

      # TODO: Remove this field once we deprecate the existing viewer_can_update in Updatable and replace with this one
      field :viewer_can_update_next, Boolean,
        description: "Check if the current viewer can update this object.",
        null: true, visibility: :internal

      def viewer_can_update_next
        T.bind(self, Platform::Interfaces::Updatable)
        viewer_can_update
      end

      field :viewer_can_type, Boolean,
        description: "Check if the current viewer can type the object",
        null: true, visibility: :internal

      def viewer_can_type
        if viewer = @context[:viewer]
          with_database_error_fallback(fallback: -> { raise Platform::Errors::ServiceUnavailable, "Viewer type update permissions are currently unavailable." }) do
            @object.async_repository.then do |repository|
              Promise.all([repository.async_owner, @object.async_can_set_type?(actor: viewer)]).then do |owner, can_type|
                owner.issue_types_enabled? && can_type
              end
            end
          end
        else
          false
        end
      end

      field :viewer_can_update_metadata, Boolean,
        description: "Check if the current viewer can update this issue's metadata.",
        null: true, visibility: :internal

      def viewer_can_update_metadata
        if viewer = @context[:viewer]
          with_database_error_fallback(fallback: -> { raise Platform::Errors::ServiceUnavailable, "Viewer metadata update permissions are currently unavailable." }) do
            issue_permissions(@object, viewer, :triageable)
          end
        else
          false
        end
      end

      field :closed_by_pull_requests_references,
        resolver: Resolvers::ClosedByPullRequestsReferences,
        null: true,
        description: "List of open pull requests referenced from this issue",
        connection: true

      field :is_transfer_in_progress, Boolean, null: false, description: "Is this issue currently being transferred", visibility: :internal
      def is_transfer_in_progress
        @object.async_is_transfer_in_progress?
      end

      field :is_read_by_viewer, Boolean, null: true, description: "Is this issue read by the viewer"

      def is_read_by_viewer
        if viewer = @context[:viewer]
          with_async_database_error_fallback(
            @object.async_batch_is_read_by_viewer(viewer),
            fallback: -> { raise Platform::Errors::ServiceUnavailable, "Viewer read status is currently unavailable." }
          )
        else
          true
        end
      end

      field :possible_transfer_repositories_for_viewer, Connections::Repository, null: true, description: "Repositories that the viewer can transfer this issue to", visibility: :internal do
        argument :query, String, "A name to search by", required: false
      end
      def possible_transfer_repositories_for_viewer(query: nil)
        if viewer = @context[:viewer]
          @object.async_possible_transfer_repositories(viewer: viewer, query: query).then do |repos|
            Platform::ArrayWrapper.new(repos)
          end
        else
          ArrayWrapper.new([])
        end
      end

      field :hovercard, Objects::Hovercard, description: "The hovercard information for this issue", null: false do
        argument :include_notification_contexts, Boolean, "Whether or not to include notification contexts", required: false, default_value: true
      end

      def hovercard(include_notification_contexts: true)
        ::IssueOrPullRequestHovercard.new(@object, viewer: @context[:viewer], include_notifications: include_notification_contexts)
      end

      field :is_pinned, Boolean, description: "Indicates whether or not this issue is currently pinned to the repository issues list", null: true

      def is_pinned
        @object.async_pinned_issue.then do
          @object.pinned?
        end
      end

      field :linked_branches, Connections::LinkedBranch, description: "Branches linked to this issue.", null: false

      def linked_branches
        ::BranchIssueReference.async_filtered_branch_issue_references_for(viewer: @context[:viewer], issue: @object).then do |accessible_linked_branches|
          ArrayWrapper.new(accessible_linked_branches)
        end
      end

      field :issue_type, Objects::IssueType, "The issue type for this Issue", null: true

      def issue_type
        return nil if @object.issue_type_id.nil?

        @object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            next unless owner.issue_types_enabled?

            @object.async_batch_issue_type.then do |issue_type|
              next unless issue_type
              T.cast(owner, ::Organization).async_readable_issue_types_matrix(@context[:viewer]).then do |matrix|
                issue_type if issue_type.readable?(matrix)
              end
            end
          end
        end
      end

      field :viewer_can_see_issue_type,
      Boolean,
      visibility: :internal,
      description: "Indicates if the viewer can see the issue type",
      null: false

      def viewer_can_see_issue_type
        @object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            owner.issue_types_enabled?
          end
        end
      end

      field :viewer_can_transfer,
        Boolean,
        visibility: :internal,
        description: "Indicates if the viewer can transfer the issue.",
        null: false

      def viewer_can_transfer
        return false unless @context[:viewer]
        @object.async_transferrable_by?(@context[:viewer])
      end

      field :viewer_can_convert_to_discussion,
        Boolean,
        visibility: :internal,
        description: "Indicates if the viewer can convert the issue to a discussion.",
        null: true

      def viewer_can_convert_to_discussion
        return false unless @context[:viewer]
        @object.async_can_be_converted_by?(@context[:viewer])
      end

      field :parent, Objects::Issue,
        description: "The parent entity of the issue.",
        null: true

      sig { returns(T.nilable(Promise[T.nilable(::Issue)])) }
      def parent
        return unless SubIssuesFeature.enabled?(@object.repository)
        @object.async_filtered_parent(viewer: context[:viewer], cap_filter: context[:cap_filter]).then do |parent|
          parent
        end
      end

      field :sub_issues_summary, Objects::SubIssuesSummary,
        description: "Summary of the state of an issue's sub-issues",
        null: false

      def sub_issues_summary
        return { total: 0, completed: 0, percent_completed: 0 } unless SubIssuesFeature.enabled?(@object.repository)
        should_recalculate = context[:recalculate_sub_issues_summary_issue_id] == @object.id
        @object.async_sub_issues_summary(calculate: should_recalculate).then do |summary|
          summary
        end
      end

      field :viewer_can_link_branches,
        Boolean,
        visibility: :internal,
        description: "Indicates if the viewer can link branches to an issue",
        null: false

      def viewer_can_link_branches
        return false unless @context[:viewer]
        @object.async_repository.then do |repo|
          repo.async_issues_and_prs_linkable_by?(context[:viewer])
        end
      end

      field :viewer_can_lock,
        Boolean,
        visibility: :internal,
        description: "Indicates if the viewer can lock/unlock the issue.",
        null: true

      def viewer_can_lock
        return false unless @context[:viewer]
        @object.async_lockable_by?(@context[:viewer])
      end

      field :sub_issues, resolver: Platform::Resolvers::SubIssues,
        description: "A list of sub-issues associated with the Issue."

      field :viewer_custom_subscription_events, [Enums::ThreadSubscriptionEvent], description: "Custom issue events the viewer is subscribed to", null: true, visibility: :internal

      def viewer_custom_subscription_events
        viewer = @context[:viewer]
        return [] if viewer.nil?

        @object.async_subscription_status(viewer).then do |subscription_status_response|
          if subscription_status_response.failed?
            raise Platform::Errors::ServiceUnavailable.new("Subscriptions are currently unavailable. Please try again later.")
          end

          subscription = subscription_status_response.value

          # Events are deprecated and not available in notifyd subscriptions. They're only available in subscriptions using newsies.
          # This was added to reintroduce custom issue notification subscriptions for Issues React.
          # We want to avoid "merged" events while the investigation in https://github.com/github/notifications/issues/4098 is ongoing and the root cause is mitigated.
          valid_events = %w[closed reopened]
          (subscription.try(:events) || []).map(&:downcase).select { |event| valid_events.include?(event) }
        end
      end
    end
  end
end
