# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequest < Platform::Objects::Base
      include Scientist

      description "A repository pull request."

      implements_node templates: [[:rpr, :repo_id, :pull_request_id]], as: "PR", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |pull_request|
        pull_request.async_repository.then do |repo|
          {
            prefix: :rpr,
            repo_id: repo.id,
            pull_request_id: pull_request.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, pull)
        Promise.all([
          permission.async_repo_and_org_owner(pull),
          pull.async_issue
        ]).then do |repo_and_org_owner, _issue|
          repo, org = repo_and_org_owner
          permission.access_allowed?(:get_pull_request,
            repo: repo,
            resource: pull,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            # Allow pull requests on public repos to be returned even when the current GitHub app isn't installed on the repo
            approved_integration_required: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_hide_from_user?(permission.viewer).then do |hide_from_user|
          if hide_from_user
            false
          else
            permission.belongs_to_repository(object)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Assignable
      implements Interfaces::Closable
      implements Interfaces::Comment
      implements Interfaces::Commentable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment
      implements Interfaces::Labelable
      implements Interfaces::Lockable
      implements Interfaces::PerformableViaApp
      implements Interfaces::Reactable
      implements Interfaces::Reportable
      implements Interfaces::MentionSuggestable
      implements Interfaces::OrgBlockable
      implements Interfaces::AbuseReportable
      implements Interfaces::RepositoryNode
      implements Interfaces::Subscribable
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Trigger
      implements Interfaces::ProjectNextOwner
      implements Interfaces::ProjectV2Owner
      implements Interfaces::MarkdownPreviewable
      implements Interfaces::SafeUser

      url_fields(description: "The HTTP URL for this pull request.") { |pull| pull.async_path_uri }

      DeprecationNotice = {
        start_date: Date.new(2024, 3, 1),
        reason: "`databaseId` will be removed because it does not support 64-bit signed integer identifiers.",
        superseded_by: "Use `fullDatabaseId` instead.",
        owner: "JanKoszewski",
      }

      database_id_field(deprecated: DeprecationNotice)
      full_database_id_field

      field :number, Integer, description: "Identifies the pull request number.", null: false

      def number
        @object.async_issue.then(&:number)
      end

      field :participants, resolver: Resolvers::Participants, description: "A list of Users that are participating in the Pull Request conversation.", connection: true

      field :base_ref, Ref, description: "Identifies the base Ref associated with the pull request.", null: true

      def base_ref
        @object.async_base_repository.then do |repository|
          repository.async_network.then do
            repository.heads.async_find(@object.base_ref)
          end
        end
      end

      field :base_ref_name, String, description: "Identifies the name of the base Ref associated with the pull request, even if the ref has been deleted.", null: false

      def base_ref_name
        @object.base_ref.dup.force_encoding("utf-8")
      end

      field :base_ref_oid, Scalars::GitObjectID,
        description: "Identifies the oid of the base ref associated with the pull request, even if the ref has been deleted.",
        null: false,
        method: :base_sha

      field :base_repository, Repository,
        description: "The repository associated with this pull request's base Ref.",
        null: true,
        method: :async_base_repository

      field :closed_by, Interfaces::Actor, visibility: :internal, description: "The actor who closed the pull request.", null: true

      def closed_by
        @object.async_issue.then(&:async_closed_by)
      end

      field :closing_issues_references, resolver: Resolvers::ClosingIssueReferences,
        null: true, description: "List of issues that may be closed by this pull request", connection: true do
        argument :order_by, Inputs::IssueOrder, "Ordering options for issues returned from the connection", required: false
      end

      field :is_read_by_viewer, Boolean, null: true, description: "Is this pull request read by the viewer"

      def is_read_by_viewer
        if viewer = @context[:viewer]
          @object.async_issue.then { |issue| issue.async_batch_is_read_by_viewer(viewer) }
        else
          true
        end
      end

      field :head_ref, Ref, description: "Identifies the head Ref associated with the pull request.", null: true

      def head_ref
        Loaders::ActiveRecord.load(::Repository, @object.head_repository_id, security_violation_behaviour: :nil).then do |repository|
          if repository.nil? # repo has been destroyed after the PR was opened, or repo is not accessible
            nil
          else
            repository.async_network.then do
              repository.heads.find(@object.head_ref)
            end
          end
        end
      end

      field :head_ref_name, String, description: "Identifies the name of the head Ref associated with the pull request, even if the ref has been deleted.", null: false

      def head_ref_name
        @object.head_ref.dup.force_encoding("utf-8")
      end

      field :head_ref_oid, Scalars::GitObjectID,
        description: "Identifies the oid of the head ref associated with the pull request, even if the ref has been deleted.",
        null: false,
        method: :head_sha

      field :head_repository, Repository, description: "The repository associated with this pull request's head Ref.", null: true

      def head_repository
        Loaders::ActiveRecord.load(::Repository, @object.head_repository_id, security_violation_behaviour: :nil)
      end

      field :head_repository_owner, Interfaces::RepositoryOwner, description: "The owner of the repository associated with this pull request's head Ref.", null: true

      def head_repository_owner
        @object.async_head_user.then do |user|
          if user&.spammy?
            nil
          else
            user
          end
        end
      end

      field :base_repository_owner, Interfaces::RepositoryOwner, visibility: :internal, description: "The owner of the repository associated with this pull request's base Ref.", null: true

      def base_repository_owner
        @object.async_base_user.then do |user|
          user&.spammy? ? nil : user
        end
      end

      field :is_cross_repository, Boolean, method: :cross_repo?, description: "The head and base repositories are different.", null: false

      field :is_draft, Boolean, description: "Identifies if the pull request is a draft.", null: false, method: :draft?

      field :state, Enums::PullRequestState, description: "Identifies the state of the pull request.", null: false

      def state
        @object.async_issue_state
      end

      field :maintainer_can_modify, Boolean, description: "Indicates whether maintainers can modify the pull request.", null: false

      def maintainer_can_modify
        @object.async_issue.then do
          @object.fork_collab_granted?
        end
      end

      field :milestone, Objects::Milestone, description: "Identifies the milestone associated with the pull request.", null: true

      def milestone
        @object.async_issue.then(&:async_milestone)
      end

      field :issue_database_id, Integer, visibility: :internal, description: "The pull request issue's database ID. This is a legacy requirement of the REST API and should never be exposed publicly.", null: false

      def issue_database_id
        @object.async_issue.then(&:id)
      end

      field :title, String, description: "Identifies the pull request title.", null: false

      def title
        @object.async_issue.then(&:title)
      end

      field :title_html, Scalars::HTML, description: "Identifies the pull request title rendered to HTML.", null: false

      def title_html
        title = @object.async_issue.then(&:title).value
        GitHub::Goomba::TitleMarkdownFilter.call(title)
      end

      field :task_list_item_count, Integer, required_capabilities: [:mobile_only_schema_mask], description: "Number of tasks in the pull request's task list", null: false do
        argument :statuses, [Enums::TaskListItemStatus, null: true], "Limit the count to tasks in the specified statuses.", required: false
      end

      def task_list_item_count(**arguments)
        @object.async_issue.then do |issue|
          issue.async_task_list_item_count(*arguments[:statuses])
        end
      end

      field :viewer_can_edit_files, Boolean, null: false, description: "Can the viewer edit files within this pull request."

      def viewer_can_edit_files
        @object.async_files_editable_by?(context[:viewer])
      end

      field :merge_queue_entry, Objects::MergeQueueEntry, description: "The merge queue entry of the pull request in the base branch's merge queue", null: true, method: :async_merge_queue_entry,
        visibility: { public: { environments: [:dotcom, :enterprise] } }

      field :merge_queue, Objects::MergeQueue,
        description: "The merge queue for the pull request's base branch", null: true, method: :async_merge_queue

      field :is_in_merge_queue, Boolean, description: "Indicates whether the pull request is in a merge queue", null: false, method: :async_in_merge_queue?

      field :is_merge_queue_enabled, Boolean,
        description: "Indicates whether the pull request's base ref has a merge queue enabled.", null: false,
        method: :async_merge_queue_enabled?

      field :viewer_can_merge_as_admin, Boolean,
        description: "Indicates whether the viewer can bypass branch protections and merge the pull request immediately",
        null: false

      def viewer_can_merge_as_admin
        @object.async_can_merge_as_admin?(context[:viewer])
      end

      field :viewer_can_add_and_remove_from_merge_queue, Boolean, feature_flag: :merge_queue, description: "Indicates whether the viewer can add and remove from the merge queue of the pull request.", null: false

      def viewer_can_add_and_remove_from_merge_queue
        @object.async_can_add_to_merge_queue?(context[:viewer])
      end

      field :og_image_url, Scalars::URI,
        description: "The image URL used to represent this resource in open graph data",
        visibility: :internal,
        method: :async_og_image_url,
        null: true

      field :diff, Objects::Diff, required_capabilities: [:mobile_only_schema_mask], description: "Identifies a diff over two commits within this pull request.", null: true, extras: [:lookahead] do
        argument :timeout, Integer, "How long to allow for loading the diff.", required: false
        argument :start_oid, String, "A commit sha to specify the beginning for a diff.", required: false
        argument :end_oid, String, "A commit sha to specify the ending for a diff.", required: false
      end

      def diff(lookahead:, timeout: nil, start_oid: nil, end_oid: nil)
        @object.async_compare_repository.then do |compare_repo|
          @object.async_merge_base.then do |merge_base_oid|
            next unless merge_base_oid
            @context.scoped_merge!(root_commit_arguments: { oid: @object.head_sha })

            async_context_lines = if GitHub.flipper[:comment_outside_the_diff].enabled?(compare_repo)
              additional_context_line_ranges = Hash.new { |h, k| h[k] = [] }

              @object.async_review_threads_for(@context[:viewer]).then do |threads|
                threads.each_with_object(additional_context_line_ranges) do |thread, accumulated_range_hash|
                  begin
                    accumulated_range_hash[thread.path] << thread.blob_context_line_range if thread&.live?
                  rescue NoMethodError
                    nil
                  end
                end
              end
            else
              Promise.resolve({})
            end

            start_ref = start_oid || merge_base_oid
            end_ref = end_oid || @object.head_sha

            async_context_lines.then do |context_lines|
              use_summary = Helpers::Diff.use_summary?(lookahead)
              algorithm = if @object.ignore_whitespace?(context[:viewer])
                GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
              else
                GitRPC::Diff::ALGORITHM_DEFAULT
              end

              Helpers::Diff.for(head_repo_id:     @object.head_repository_id,
                                base_repo_id:     @object.base_repository_id,
                                start_ref_or_oid: start_ref,
                                end_ref_or_oid:   end_ref,
                                base_commit_oid:  merge_base_oid,
                                use_summary:      use_summary,
                                timeout:          timeout,
                                compare_repo:     compare_repo,
                                context_lines:    context_lines,
                                pull_request:     @object,
                                algorithm:        algorithm
                              )
            end
          end
        end
      end

      field :files, Connections.define(Objects::PullRequestChangedFile), description: "Lists the files changed within this pull request.", null: true

      def files
        @object.async_historical_comparison.then do |comparison|
          diff = comparison.init_diffs
          diff.use_summary = true

          next unless diff.summary.available?

          files = diff.summary.deltas.map do |delta|
            ::PullRequest::ChangedFile.new(
              path: delta.path,

              # these can be null in the case of binary files. Our API can't handle that so let's
              # set them to 0 instead.
              additions: delta.additions || 0,
              deletions: delta.deletions || 0,
              status: delta.status_label,
              repository: @object.repository,
              pull_request: @object,
            )
          end

          ArrayWrapper.new(files)
        end
      end

      # Note: This field resolver overrides the definition provided in Interfaces::Comment to add support
      # for these arguments. This logic is duplicated across several GraphQL objects:
      # - Discussion, DiscussionComment, Issue, IssueComment, PullRequest, PullRequestReview, and PullRequestReviewComment
      #
      # Please ensure that your changes are reflected in all of the relevant resolvers.
      field :body_html, Scalars::HTML, description: "The body rendered to HTML.", null: false do
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blobs", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, required_capabilities: [:mobile_only_schema_mask]
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_mobile_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks using Mobile-specific HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask, :mobile_body_markup]
      end

      def body_html(hide_code_blobs: false, render_suggested_changes_as_text: false, scrub_video: nil, unfurl_references: false, include_suggested_changes_id: false, render_mobile_tasklist_blocks: false)
        if Apps::Privileged.capable?(:video_scrubbable, app: context[:oauth_app]) && scrub_video.nil?
          scrub_video = true
        end

        @object.async_issue.then do |issue|
          issue.async_repository.then do |repo|
            Promise.all([repo.async_owner, repo.async_network]).then do
              context = {
                viewer: @context[:viewer],
                cap_filter: @context[:cap_filter],
                unfurl_references: unfurl_references,
                hide_code_blobs: hide_code_blobs,
                scrub_video: scrub_video,
                render_mobile_tasklist_blocks: render_mobile_tasklist_blocks
              }

              @object.async_body_html(context: context).then do |body_html|
                body_html || GitHub::HTMLSafeString::EMPTY
              end
            end
          end
        end
      end

      field :body_version, String, visibility: :internal, description: "Identifies the body hash of the pull request.", null: false

      def body_version
        @object.async_issue.then(&:body_version)
      end

      field :editor, Interfaces::Actor, description: "The actor who edited this pull request's body.", null: true

      def editor
        @object.async_issue.then do |issue|
          ::Platform::Helpers::Editor.for(editable: issue, context: @context)
        end
      end

      field :last_edited_at, Scalars::DateTime, description: "The moment the editor made the last edit", null: true

      def last_edited_at
        @object.async_issue.then do |issue|
          issue.async_latest_user_content_edit.then do |user_content_edit|
            user_content_edit.edited_at if user_content_edit
          end
        end
      end

      field :closed, Boolean, description: "`true` if the pull request is closed", null: false

      def closed
        @object.async_issue.then do
          @object.closed?
        end
      end

      field :locked, Boolean, description: "`true` if the pull request is locked", null: false

      def locked
        @object.async_issue.then do |issue|
          issue.async_locked?
        end
      end

      field :required_status_checks, Connections.define(Objects::RequiredStatusCheck), description: "A list of required status checks expected for this commit.", required_capabilities: [:mobile_only_schema_mask], null: false, connection: true

      def required_status_checks
        @object.async_base_repository.then do |repository|
          repository.async_network.then do
            repository.async_owner.then do
              repository.async_plan_customer.then do
                repository.async_organization.then do
                  policy_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repository, @object.base_ref)
                  if policy_evaluator
                    policy_evaluator.async_required_status_checks.then do |required_status_checks|
                      ArrayWrapper.new(required_status_checks.map do |check|
                        Platform::Models::RequiredStatusCheck.new(check, repository)
                      end)
                    end
                  else
                    ArrayWrapper.new([])
                  end
                end
              end
            end
          end
        end
      end

      field :mergeable, Enums::MergeableState, description: "Whether or not the pull request can be merged based on the existence of merge conflicts.", null: false

      def mergeable
        Loaders::PullRequestMergesCleanly.load(@object.id).then do |merges_cleanly|
          if merges_cleanly == true
            "mergeable"
          elsif merges_cleanly == false
            "unmergeable"
          else
            "unknown"
          end
        end
      end

      field :merge_requirements, Objects::PullRequestMergeRequirements, description: "The current requirements for the pull request to merge", null: false, feature_flag: :pull_request_merge_requirements_api, required_capabilities: [:mobile_only_schema_mask] do
        argument :merge_action, Enums::PullRequestMergeAction, "The strategy to evaluate mergeability using", required: false
        argument :merge_method, Enums::PullRequestMergeMethod, "The method to evaluate mergeability using", required: false
        argument :bypass_requirements, Boolean, "Determines if the merge requirments should be ignored", required: false, default_value: false
      end

      def merge_requirements(**arguments)
        viewer = context[:viewer]

        possible_author_email_sources = [
          viewer.async_primary_user_email,
          viewer.async_primary_private_user_email,
          viewer.async_stealth_user_email,
          viewer.async_profile,
        ]

        # We need to ensure deeper calls honor GraphQL async loading.
        Promise.all(possible_author_email_sources).then do
          ::PullRequest::MergeRequirements.new(
            object,
            arguments[:merge_action],
            arguments[:merge_method],
            arguments[:bypass_requirements],
            viewer,
            skip_checks: false
          )
        end
      end

      field :viewer_merge_actions,
        [Platform::Objects::AllowablePullRequestMergeAction],
        required_capabilities: [:mobile_only_schema_mask],
        null: false,
        description: "A list of potential ways the viewer could attempt to merge this pull request."

      def viewer_merge_actions
        ::PullRequest::AllowableMergeAction.for(pull_request: @object, viewer: context[:viewer])
      end

      field :merge_state_status, Enums::MergeStateStatus, description: "Detailed information about the current pull request merge state status.", null: false

      def merge_state_status
        Promise.all([@object.async_repository,
                     @object.async_base_repository,
                     @object.async_head_repository,
                     @object.async_merge_queue
        ]).then do |result|
          merge_queue = result.pop
          repositories = result

          if merge_queue
            GitHub::PrefillAssociations.prefill_associations(merge_queue, :repository, available_records: repositories)
          end

          # This prefills repository networks and plan customers
          GitHub::PrefillAssociations.prefill_batch_method(repositories, :plan_customer_disabled?)
          users = [@object.async_base_user, @object.async_head_user, @object.async_user]

          Promise.all(users).then do
            base_repo = repositories[1]
            @object.enqueue_mergeable_update
            @object.merge_state(viewer: @context[:viewer]).async_status
          end
        end
      end

      field :viewer_merge_body_text, String, null: false, description: "The merge body text for the viewer and method." do
        argument :merge_type, Enums::PullRequestMergeMethod, "The merge method for the message.", required: false
      end

      def viewer_merge_body_text(merge_type: nil)
        @object.async_repository.then do
          merge_method = merge_type || @object.default_merge_method_for(@context[:viewer])

          case merge_method
          when :merge
            @object.default_merge_commit_message
          when :squash
            @object.async_user.then do |user|
              if user
                user.async_emails.then do
                  @object.async_changed_commits.then do
                    @object.default_squash_commit_message
                  end
                end
              else
                @object.async_changed_commits.then do
                  @object.default_squash_commit_message
                end
              end
            end
          else
            ""
          end
        end
      end

      field :viewer_merge_headline_text, String, null: false, description: "The merge headline text for the viewer and method." do
        argument :merge_type, Enums::PullRequestMergeMethod, "The merge method for the message.", required: false
      end

      def viewer_merge_headline_text(merge_type: nil)
        @object.async_repository.then do
          merge_method = merge_type || @object.default_merge_method_for(@context[:viewer])

          @object.async_head_user.then do
            case merge_method
            when :merge
              @object.default_merge_commit_title
            when :squash
              @object.async_changed_commits.then do
                @object.default_squash_commit_title
              end
            else
              ""
            end
          end
        end
      end

      field :merged, Boolean, method: :merged?, description: "Whether or not the pull request was merged.", null: false

      field :merged_at, Scalars::DateTime, description: "The date and time that the pull request was merged.", null: true

      field :merged_by, Interfaces::Actor, description: "The actor who merged the pull request.", null: true

      def merged_by
        return unless @object.merged?

        @object.async_issue.then do |issue|
          issue.async_events.then do |events|
            merge_events = events.select(&:merge?)
            next if merge_events.empty?

            merge_events.last.async_actor.then do |actor|
              if actor&.spammy?
                nil
              else
                actor
              end
            end
          end
        end
      end

      field :merge_commit, Objects::Commit, description: "The commit that was created when this pull request was merged.", null: true

      def merge_commit
        return nil unless @object.merged?

        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.merge_commit_sha, expected_type: :commit)
        end
      end

      field :potential_merge_commit, Objects::Commit, description: "The commit that GitHub automatically generated to test if this pull request could be merged. This field will not return a value if the pull request is merged, or if the test merge commit is still being generated. See the `mergeable` field for more details on the mergeability of the pull request.", null: true

      def potential_merge_commit
        return nil if @object.merged?

        Loaders::PullRequestMergesCleanly.load(@object.id).then do |merges_cleanly|
          if merges_cleanly && @object.merge_commit_sha
            Loaders::ActiveRecord.load(::Repository, @object.base_repository_id).then do |base_repo|
              Loaders::GitObject.load(base_repo, @object.merge_commit_sha, expected_type: :commit)
            end
          end
        end
      end

      field :auto_merge_request, Objects::AutoMergeRequest, description: "Returns the auto-merge request object if one exists for this pull request.", null: true

      def auto_merge_request
        @object.async_auto_merge_request
      end

      field :comparison, Objects::PullRequestComparison, visibility: :internal, description: "The pull request's comparison.", null: true do
        argument :start_oid, String, "A commit sha to specify the beginning of a comparison.", required: false
        argument :end_oid, String, "A commit sha to specify the ending of a comparison.", required: false
        argument :single_commit_oid, String, "A commit sha that specifies the commit to show as the comparison.", required: false
      end

      sig { params(start_oid: T.nilable(String), end_oid: T.nilable(String), single_commit_oid: T.nilable(String)).returns(Promise[::PullRequest::Comparison]) }
      def comparison(start_oid: nil, end_oid: nil, single_commit_oid: nil)
        raise Errors::ArgumentError, "Passing a commit range and a single commit is not supported" if (!start_oid.nil? || !end_oid.nil?) && !single_commit_oid.nil?

        Promise.all([
          @object.async_compare_repository,
          @object.async_base_repository,
          @object.async_head_repository,
          @object.async_merge_base
        ]).then do |compare_repo, base_repo, head_repo, merge_base_oid|
          next if compare_repo.nil?
          next if merge_base_oid.nil?

          if single_commit_oid
            repo_commit_oid = T.let(compare_repo.commits.find(single_commit_oid).parent_oids.first, T.nilable(String))
            start_oid = repo_commit_oid
            end_oid = single_commit_oid
          end

          ::PullRequest::Comparison.async_find(
            pull: @object,
            start_commit_oid: start_oid || merge_base_oid,
            end_commit_oid: end_oid || @object.head_sha,
            base_commit_oid: merge_base_oid,
            use_summary: true,
            ignore_whitespace: @object.ignore_whitespace?(context[:viewer]),
            base_repository: base_repo,
            head_repository: head_repo,
          )
        end
      end

      field :comment, Objects::IssueComment,
          description: "Find a particular comment on this pull request.",
          visibility: :under_development, null: true do
        argument :database_id, Int, "Look up comment by its database ID.", required: true
      end

      def comment(database_id:)
        @object.async_issue.then do |issue|
          if context[:permission].typed_can_access?("Issue", issue)
            issue.comments.filter_spam_for(@context[:viewer]).where(id: database_id).first
          end
        end
      end

      field :review_comment, Objects::PullRequestReviewComment,
          description: "Find a particular comment in a review on this pull request.",
          visibility: :under_development, null: true do
        argument :database_id, Int, "Look up comment by its database ID.", required: true
      end

      def review_comment(database_id:)
        @object.review_comments.filter_spam_for(@context[:viewer]).where(id: database_id).first
      end

      field :review, Objects::PullRequestReview,
          description: "Find a particular code review of this pull request.",
          visibility: :under_development, null: true do
        argument :database_id, Int, "Look up review by its database ID.", required: true
      end

      def review(database_id:)
        reviews.where(id: database_id).first
      end

      field :comments, resolver: Resolvers::IssueComments, description: "A list of comments associated with the pull request.", connection: true, numeric_pagination_enabled: true

      field :total_comments_count, Integer,
        null: true,
        method: :total_comments,
        description: "Returns a count of how many comments this pull request has received."

      field :review_threads, Connections.define(Objects::PullRequestReviewThread),
        description: "The list of all review threads for this pull request.",
        connection: true,
        null: false do
          argument :path, String, "The blob path the review threads target", required: false, visibility: :internal
          argument :subject_type, Enums::PullRequestReviewThreadSubjectType, "The subject type of the review thread", required: false, visibility: :internal
        end

      def review_threads(**arguments)
        Loaders::PullRequest::ReviewThreads.load(@object.id, @context[:viewer], **arguments.slice(:path, :subject_type)).then do |threads|
          StableArrayWrapper.new(threads)
        end
      end

      field :threads, Connections.define(Objects::PullRequestThread),
        description: "The list of all review threads for this pull request.",
        connection: true,
        visibility: :under_development,
        null: false do
          argument :start_commit_oid, String, "The start commit OID of the threads", required: false
          argument :end_commit_oid, String, "The end commit OID of the threads", required: false
          argument :is_positioned, Boolean, "Skip positioning comments within diff", default_value: true, required: false
          argument :path, String, "The blob path the review threads target", required: false, visibility: :internal
          argument :subject_type, Enums::PullRequestReviewThreadSubjectType, "The subject type of the review thread", required: false, visibility: :internal
          argument :order_by, Enums::PullRequestReviewThreadOrderField, "Order threads by this field", required: false, visibility: :internal, default_value: "created_at"
        end

      def threads(**arguments)
        arguments[:order_by] ||= "created_at"
        raise Errors::ArgumentError, "Filtering by subjectType = FILE is not supported with positioned threads." if arguments[:subject_type] == "file" && arguments[:is_positioned]

        arg_filter = -> (pr_thread) do
          matches_path = arguments[:path].blank? || pr_thread.review_thread.path == arguments[:path]
          matches_type = arguments[:subject_type].blank? || pr_thread.review_thread.subject_type == arguments[:subject_type]

          matches_path && matches_type
        end

        diff_position_sorter = -> (a, b) do
          path_comparison = Helpers::PathComparer.compare_paths(a.path, b.path)
          return path_comparison unless path_comparison == 0

          a_position = a.position || 0
          b_position = b.position || 0
          position_comparison = a_position <=> b_position
          return position_comparison unless position_comparison == 0

          a.created_at <=> b.created_at
        end

        order_by_diff_position = arguments[:order_by] == "diff_position"

        if arguments[:is_positioned]
          # TODO: positioned threads only ever return LINE-level threads. Figure out how subject_type and is_positioned coexist.

          async_pr_comparison = @object.async_pull_comparison(start_oid: arguments[:start_commit_oid], end_oid: arguments[:end_commit_oid])
          async_pr_comparison.then do |comparison|
            next unless comparison
            thread_positioner = comparison.thread_positioner(viewer: @context[:viewer])

            thread_positioner.positioned_threads
          end
        else
          Loaders::PullRequest::ReviewThreads.load(@object.id, @context[:viewer])
        end.then do |threads|
          return ArrayWrapper.new([]) if threads.nil?

          threads = threads.sort(&diff_position_sorter) if order_by_diff_position

          filtered_pull_request_threads = threads.map do |thread|
            Platform::Models::PullRequestThread.new(thread)
          end.select(&arg_filter)

          if order_by_diff_position
            ArrayWrapper.new(filtered_pull_request_threads)
          else
            # StableArrayWrapper sorts by created_at and id by default
            StableArrayWrapper.new(filtered_pull_request_threads)
          end
        end
      end

      field :viewer_latest_review_request, Objects::ReviewRequest, description: "The person who has requested the viewer for review on this pull request.", null: true

      def viewer_latest_review_request
        return nil unless @context[:viewer]
        @object.async_user.then do
          requests = @object.review_requests_for(@context[:viewer])
          next if requests.blank?
          requests.last
        end
      end

      field :viewer_latest_review, Objects::PullRequestReview, description: "The latest review given from the viewer.", null: true

      def viewer_latest_review
        return nil unless @context[:viewer]
        @object.async_latest_non_pending_review_for(@context[:viewer])
      end

      field :viewer_pending_review, Objects::PullRequestReview, visibility: :internal, description: "The latest pending review started by the viewer.", null: true

      def viewer_pending_review
        return nil unless @context[:viewer]
        @object.latest_pending_review_for(@context[:viewer])
      end

      field :latest_review_comment_by_viewer, Objects::PullRequestReviewComment, null: true,
        description: "Latest pull request review comment created by current viewer",
        visibility: :under_development

      # TODO: Make this lookup async
      def latest_review_comment_by_viewer
        return nil unless @context[:viewer]
        review_comment = @object.review_comments
               .where(user: @context[:viewer])
               .order(updated_at: :desc)
               .first
        latest_review_request_for_viewer = @object.latest_non_pending_review_for(@context[:viewer])

        return nil if review_comment.nil?
        return review_comment if latest_review_request_for_viewer.nil?
        review_comment.updated_at == latest_review_request_for_viewer.submitted_at ? review_comment : nil
      end

      field :commits_since_viewer_last_seen, Connections.define(Objects::Commit),
        description: "A list of commits present in this pull request added after the last commit seen by the viewer.",
        null: false,
        required_capabilities: [:mobile_only_schema_mask],
        connection: true

      def commits_since_viewer_last_seen
        return ArrayWrapper.new([]) unless @context[:viewer]
        marker = @object.revision_marker(@context[:viewer])
        return ArrayWrapper.new([]) unless marker

        Promise.all([
          @object.async_changed_commits,
          marker.async_last_seen_commit
        ]).then do |commits, last_seen_commit|
          since_last_seen_commits = []
          found_non_viewer_commit = T.let(false, T::Boolean)

          ## revision_marker gets updated with the last seen commit only if this is not authored by the viewer.
          ## So we need to exclude manually the commits authored by the viewer created after the last seen commit
          ## and before the next commit authored by someone else.
          commits.each do |commit|
            if found_non_viewer_commit
              since_last_seen_commits << commit
            elsif commit.created_at > last_seen_commit.created_at && commit.author&.id != @context[:viewer].id
              found_non_viewer_commit = true
              since_last_seen_commits << commit
            end
          end

          ArrayWrapper.new(since_last_seen_commits)
        end
      end

      field :latest_opinionated_reviews, Connections.define(Objects::PullRequestReview), description: "A list of latest reviews per user associated with the pull request.", null: true, connection: true do
        argument :writers_only, Boolean, "Only return reviews from user who have write access to the repository", required: false, default_value: false
      end

      def latest_opinionated_reviews(**arguments)
        @object.async_latest_enforced_reviews(writers_only: arguments[:writers_only]).then do |reviews|
          ArrayWrapper.new(reviews.reject { |review| review.hide_from_user?(@context[:viewer]) })
        end
      end

      field :latest_reviews, Connections.define(Objects::PullRequestReview), description: "A list of latest reviews per user associated with the pull request that are not also pending review.", null: true, connection: true do
        argument :preferOpinionatedReviews, Boolean, "Replaces an author's commented review with their latest opinionated review if it exists.", required: false, visibility: :internal, default_value: false
      end

      def latest_reviews(**arguments)
        @object.async_user.then do
          if arguments[:preferOpinionatedReviews]
            @object.async_latest_reviews_preferring_opinionated_reviews(@context[:viewer]).then do |reviews|
              ArrayWrapper.new(reviews)
            end
          else
            ArrayWrapper.new(@object.visible_sidebar_reviews(@context[:viewer]))
          end
        end
      end

      field :reviews, Connections.define(Objects::PullRequestReview), numeric_pagination_enabled: true, description: "A list of reviews associated with the pull request.", null: true, connection: true do
        argument :states, [Enums::PullRequestReviewState], "A list of states to filter the reviews.", required: false
        argument :author, String, "Filter by author of the review.", required: false
      end

      def reviews(**arguments)
        scope = @object.latest_reviews_for(@context[:viewer])
        if arguments[:states]
          states = arguments[:states].map { |name| ::PullRequestReview.state_value(name) }
          scope = scope.where(state: states)
        end

        if arguments[:author]
          scope = scope.where(user_id: ::User.where(login: arguments[:author]).ids)
        end

        scope
      end

      field :commits, Connections::PullRequestCommit, max_page_size: 250, description: "A list of commits present in this pull request's head branch not present in the base branch.", null: false, connection: true

      def commits
        Promise.all([
          @object.async_repository,
          @object.async_head_repository,
          @object.async_base_repository,
          @object.async_changed_commits,
        ]).then do |repository, head_repository, base_repository, commits|
          pull_request_commits = commits.map do |commit|
            commit.repository = repository
            commit.head_repository = head_repository
            commit.base_repository = base_repository
            Models::PullRequestCommit.new(@object, commit)
          end

          ArrayWrapper.new(pull_request_commits)
        end
      end

      field :head_commit, Objects::PullRequestCommit, visibility: :internal, description: "Head commit of the pull request.", null: true

      def head_commit
        @object.async_load_pull_request_commit(@object.head_sha)
      end

      field :is_corrupt, Boolean, visibility: :internal, description: "Whether or not the pull request is corrupt.", null: false

      def is_corrupt
        @object.async_changed_commits.then do
          @object.corrupt?
        end
      end

      field :review_requests, Connections.define(Objects::ReviewRequest), description: "A list of review requests associated with the pull request.", null: true, connection: true

      def review_requests
        @object.review_requests.pending.scoped
      end

      field :can_be_rebased, Boolean, description: "Whether or not the pull request is rebaseable.", null: false

      def can_be_rebased
        @object.async_repository.then do |repository|
          Promise.all([repository.async_network, @object.async_issue]).then do
            Loaders::PullRequestMergesCleanly.load(@object.id).then do |merges_cleanly|
              (merges_cleanly == true) && @object.rebase_safe?
            end
          end
        end
      end

      field :review_decision, Enums::PullRequestReviewDecision,
        null: true,
        description: "The current status of this pull request with respect to code review."

      def review_decision
        @object.async_repository.then do |repository|
          repository.async_internal_repository.then do
            @object.async_review_decision(viewer: @context[:viewer])
          end
        end
      end

      # TODO N+1 for queries loading lots of merge events. May want to keep this field internal.
      # see https://github.com/github/github/pull/74977#discussion_r123785568 for discussion
      # on making this batch loaded.
      field :status_at_merge, Objects::Status, visibility: :internal, method: :async_status_at_merge, description: "The status contexts belonging to the last commit before merge that were created before the merge.", null: true

      field :timeline,
        resolver: Platform::Resolvers::PullRequestTimeline,
        description: "A list of events, comments, commits, etc. associated with the pull request.",
        deprecated: {
          start_date: Date.new(2020, 4, 22),
          reason: "`timeline` will be removed",
          superseded_by: "Use PullRequest.timelineItems instead.",
          owner: "mikesea",
        }

      # New, fully batched timeline powered by `Timeline::PullRequestTimeline`. We do not
      # intend to publish it with this name!
      #
      # TODO: Make the timeline paginateable and publish it by merging it into `timeline`.
      field :timeline_items,
        resolver: Platform::Resolvers::PullRequestTimelineItems,
        connection: true,
        max_page_size: 250,
        description: "A list of events, comments, commits, etc. associated with the pull request."


      field :timeline_item, Unions::PullRequestTimelineItems, description: "Get a timeline item from a url", null: true, required_capabilities: [:mobile_only_schema_mask] do
        argument :url, String, "The url to decode.", required: false
      end

      def timeline_item(url: "")
        return nil unless url.present?
        anchor = url.partition("#").last
        return nil if anchor.blank?
        name, id = anchor.scan(/\d+|\D+/)

        case name.gsub("-", "")
        when "pullrequestreview"
          @object.latest_reviews_for(context[:viewer]).find_by(id: id.to_i)
        when "issuecomment"
          @object.issue.comments.find_by(id: id.to_i)
        when "discussion_r"
          @object.review_comments.visible_to(context[:viewer]).find_by(id: id.to_i)&.async_pull_request_review_thread
        else
          nil
        end
      end

      field :suggested_reviewers, [SuggestedReviewer, null: true], description: "A list of reviewer suggestions based on commit history and past review comments.", null: false

      def suggested_reviewers(actor: nil)
        Platform::LoaderTracker.ignore_association_loads do # rubocop:disable GitHub/IgnoreAssociationLoads
          if @object.suggested_reviewers_available?(actor: context[:viewer])
            ArrayWrapper.new(@object.suggested_reviewers(actor: context[:viewer]))
          else
            ArrayWrapper.new([])
          end
        end
      end

      field :candidate_reviewers, Connections.define(Platform::Objects::CandidateReviewer), description: "A list of reviewers that match the given query.", null: false, visibility: :internal do
        argument :query, String, "The query with which to filter reviewer results", required: false
      end

      def candidate_reviewers(**arguments)
        query = arguments[:query]
        Promise.all([@object.async_issue, @object.async_user]).then do |issue, _|
          Promise.all([issue.async_repository, issue.async_user]).then do |repo, _|
            Promise.all([repo.async_owner, repo.async_organization, repo.async_plan_customer]).then do |owner, org|
              Promise.all([owner&.async_business, org&.async_business]).then do
                ArrayWrapper.new(@object.sorted_reviewers(context[:viewer], search_query: query).map do |reviewer|
                  Platform::Models::CandidateReviewer.new(reviewer: reviewer)
                end)
              end
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
        when "head_ref"
          @object.async_repository.then do |repository|
            GitHub::WebSocket::Channels.branch(repository, @object.display_head_ref_name)
          end
        when "timeline"
          GitHub::WebSocket::Channels.pull_request_timeline(@object)
        when "state"
          GitHub::WebSocket::Channels.pull_request_state(@object)
        when "presence"
          @object.async_signed_presence_channel
        end
      end

      field :updates_channel, String, "Channel value for subscribing to live updates.", null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events] do
        argument :name, Enums::PullRequestPubSubTopic, "The name of the channel to use.", required: false, default_value: "updated"
      end

      def updates_channel(**arguments)
        case arguments[:name]
        when "updated"
          GitHub::WebSocket::Channels.signed_pull_request(@object)
        when "head_ref"
          @object.async_repository.then do |repository|
            GitHub::WebSocket::Channels.signed_branch(repository, @object.display_head_ref_name)
          end
        when "base_ref"
          @object.async_base_repository.then do |base_repository|
            GitHub::WebSocket::Channels.signed_branch(base_repository, @object.display_base_ref_name)
          end
        when "commit_head_sha"
          @object.async_base_repository.then do |base_repository|
            GitHub::WebSocket::Channels.signed_commit(base_repository, @object.head_sha)
          end
        when "timeline"
          GitHub::WebSocket::Channels.signed_pull_request_timeline(@object)
        when "state"
          GitHub::WebSocket::Channels.signed_pull_request_state(@object)
        when "deployed"
          GitHub::WebSocket::Channels.signed_pull_request_deployed(@object)
        when "review_state"
          GitHub::WebSocket::Channels.signed_pull_request_review_state(@object)
        when "mergeability"
          @object.async_head_repository.then do |_|
            @object.async_base_repository.then do |_|
              GitHub::WebSocket::Channels.signed_pull_request_mergeable(@object)
            end
          end
        when "workflows"
          GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(@object)
        when "merge_queue"
          GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(@object)
        when "git_merge_state"
          GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(@object)
        end
      end

      field :project_cards, resolver: Resolvers::ProjectCards, connection: false, null: false, description: "List of project cards associated with this pull request.", deprecated: Helpers::ProjectDeprecation::Notice

      field :project_next_items, resolver: Resolvers::ProjectNextItems,
        description: "List of project items associated with this pull request.",
        required_capabilities: [:mobile_only_schema_mask]

      field :project_items, resolver: Resolvers::ProjectV2Items,
        description: "List of project items associated with this pull request."

      # TODO: Remove this field once we deprecate the existing project_items and replace with this nullable version
      field :project_items_next, resolver: Resolvers::ProjectV2Items,
      description: "List of project items associated with this pull request.",
      visibility: :internal, null: true

      url_fields prefix: :revert, description: "The HTTP URL for reverting this pull request." do |pull|
        pull.async_revert_path_uri
      end

      url_fields prefix: :checks, description: "The HTTP URL for the checks of this pull request." do |pull|
        pull.async_repository.then do |repository|
          repository.async_owner.then do |owner|
            template = Addressable::Template.new("/{user}/{repo}/pull/{pull_number}/checks")
            template.expand user: owner.display_login, repo: repository.name, pull_number: pull.number
          end
        end
      end

      url_fields prefix: :restore_head_ref, description: "The HTTP URL for restoring this pull request's head ref.", visibility: :internal do |pull|
        pull.async_restore_head_ref_path_uri
      end

      field :viewer_preferences, Objects::PullRequestUserPreferences, "The viewer's pull request settings", null: false, visibility: :internal

      def viewer_preferences
        Platform::Models::PullRequestUserPreferences.new(user: @context[:viewer], pull_request: @object)
      end

      field :viewer_can_restore_head_ref, Boolean, "Check if the viewer can restore the deleted head ref.", visibility: :internal, null: false

      def viewer_can_restore_head_ref
        @object.async_head_ref_restorable_by?(@context[:viewer])
      end

      field :viewer_can_delete_head_ref, Boolean, "Check if the viewer can restore the deleted head ref.", null: false

      def viewer_can_delete_head_ref
        @object.async_head_ref_deleteable_by?(@context[:viewer]).then do |deleteable|
          next true if deleteable

          @object.async_head_ref_deleteable_after_updating_dependents?(@context[:viewer])
        end
      end

      field :viewer_has_pending_review, Boolean, visibility: :internal, description: "Check if the viewer has a pending review on this pull request.", null: false

      def viewer_has_pending_review
        @object.async_pending_review_by?(@context[:viewer])
      end

      field :additions, Integer, description: "The number of additions in this pull request.", null: false, method: :async_additions

      field :deletions, Integer, description: "The number of deletions in this pull request.", null: false, method: :async_deletions

      field :changed_files, Integer, description: "The number of changed files in this pull request.", null: false, method: :async_changed_files

      # This should be kept internal until the tooltip dismissal action is on a user controller instead.
      # There is nothing inherently making this function dependent on pull requests.
      url_fields(prefix: :dismiss_merge_tip,
                       description: "The HTTP URL to dismiss merge tips for the viewer.",
                       visibility:  :internal) do |pull|
        pull.async_dismiss_merge_tip_path_uri
      end

      field :permalink, Scalars::URI, description: "The permalink to the pull request.", null: false

      def permalink
        @object.async_repository.then do
          @object.async_issue.then do
            Addressable::URI.parse(@object.permalink)
          end
        end
      end

      field :viewer_can_apply_suggestion, Boolean, description: "Whether or not the viewer can apply suggestion.", null: false

      def viewer_can_apply_suggestion
        @object.suggested_change_applicable_by?(context[:viewer])
      end

      field :viewer_can_enable_auto_merge, Boolean, description: "Whether or not the viewer can enable auto-merge", null: false

      def viewer_can_enable_auto_merge
        Promise.all([@object.async_repository, @object.async_base_repository, @object.async_head_repository]).then do |repositories|
          networks = repositories.compact.map(&:async_network)
          plan_customers = repositories.compact.map(&:async_plan_customer)
          other_requirements = [@object.async_base_user, @object.async_head_user, @object.async_user, @object.async_auto_merge_request]

          Promise.all(networks + plan_customers + other_requirements).then do
            # Only enqueue this job for our mobile apps
            if Apps::Privileged.capable?(:enqueue_mergeable_update, app: context[:oauth_app])
              @object.enqueue_mergeable_update
            end

            @object.can_enable_auto_merge(actor: context[:viewer]).allowed?
          end
        end
      end

      field :viewer_can_disable_auto_merge, Boolean, description: "Whether or not the viewer can disable auto-merge", null: false

      def viewer_can_disable_auto_merge
        @object.async_auto_merge_request.then do |_auto_merge_request|
          @object.can_disable_auto_merge?(actor: context[:viewer])
        end
      end

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          repository && Loaders::PullRequestByNumber.load(repository.id, params[:id].to_i)
        end
      end

      field :hovercard, Objects::Hovercard, description: "The hovercard information for this issue", null: false do
        argument :include_notification_contexts, Boolean, "Whether or not to include notification contexts", required: false, default_value: true
      end

      def hovercard(include_notification_contexts: true)
        ::IssueOrPullRequestHovercard.new(@object, viewer: @context[:viewer], include_notifications: include_notification_contexts)
      end

      field :updated_at, Platform::Scalars::DateTime, null: false, description: "Identifies the date and time when the object was last updated."

      def updated_at
        @object.async_issue.then do |issue|
          [@object.updated_at, issue.updated_at].max
        end
      end

      field :action_required_workflow_run_count, Integer, required_capabilities: [:mobile_only_schema_mask], description: "Number of workflow runs pending approval on the pull request", null: false

      def action_required_workflow_run_count
        @object.action_required_check_suites(head_sha: @object.head_sha).size
      end

      field :viewer_can_request_copilot_code_review, Boolean, visibility: :internal, description: "Whether or not the viewer can request a Copilot code review on this PR", null: false

      def viewer_can_request_copilot_code_review
        Promise.all([@object.async_user, @object.async_repository]).then do |user, repo|
          PullRequests::Copilot::CodeReviewAccess.new(actor: user, current_repository: repo).can_create_review_request?
        end
      end

      field :viewer_has_violated_push_policy, Boolean, visibility: :internal, description: "Whether or not the viewer has violated the push policy", null: true

      def viewer_has_violated_push_policy
        @object.async_base_repository.then do
          !!@object.user_has_violated_push_rule?(context[:viewer])
        end
      end

      field :status_check_rollup, Objects::StatusCheckRollup, description: "Check and Status rollup information for the PR's head ref.", null: true, extras: [:lookahead]

      def status_check_rollup(lookahead:)
        overview_only = !lookahead.selects?(:contexts)
        @object.async_repository.then do |repo|
          Objects::StatusCheckRollup.load_from_repo_and_oid(repo, @object.head_sha, overview_only)
        end
      end

      field :viewer_can_update_branch, Boolean, description: <<~DESC, null: false
        Whether or not the viewer can update the head ref of this PR, by merging or rebasing the base ref.
        If the head ref is up to date or unable to be updated by this user, this will return false.
      DESC

      def viewer_can_update_branch
        # NOTE: The logic in this resolver is intended to be equivalent to the logic in the view model:
        #   https://github.com/github/github/blob/bd5a873f84a33bfe7985c2b861d03050059f5c2a/app/view_models/pull_requests/merge_button_view.rb#L50-L71
        viewer = context[:viewer]

        return false unless viewer
        return false if viewer.must_verify_email?

        Promise.all([
          object.async_in_merge_queue?,
          object.async_head_repository,
          object.async_base_repository,
          object.async_head_user,
          object.async_base_user,
          object.async_batch_base_branch_rule_evaluator
        ]).then do |in_merge_queue, head_repo, base_repo, _head_user, _base_user, policy_evaluator|
          next false if in_merge_queue
          next false unless head_repo

          Promise.all([head_repo.async_owner, head_repo.async_network, head_repo.async_plan_customer, base_repo.async_network, base_repo.async_plan_customer]).then do |head_repo_owner, _, _, _, _|
            next false unless head_repo_owner
            next false unless head_repo.pushable_by?(viewer, ref: object.head_ref_name)

            strict_required_status_checks_enabled =
              policy_evaluator.present? &&
              policy_evaluator.required_status_checks_enabled? &&
              policy_evaluator.strict_required_status_checks_policy? &&
              policy_evaluator.required_status_checks.any?

            next false unless strict_required_status_checks_enabled || base_repo.enable_update_branch?

            next !!object.behind_base?
          end
        end
      end

      field :codeowners, [Unions::Codeowners], description: "The codeowners for the files changed in the pull request", visibility: :internal, null: true

      def codeowners
        @object.async_codeowners.then do |codeowners|
          if codeowners.file.present?
            codeowners.repository.async_plan_customer.then do
              codeowners.async_owners_visible_to(@context[:viewer])
            end
          else
            nil
          end
        end
      end

      field :viewer_viewed_files, Integer, description: "The number of files viewed by the viewer within this pull request.", visibility: :internal, null: false

      def viewer_viewed_files
        return unless @context[:viewer]
        @object.async_viewer_viewed_files(@context[:viewer]).then do |files|
          files.count
        end
      end

      field :viewer_can_change_base_branch, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether or not the viewer can change the base branch of this pull request", null: false

      def viewer_can_change_base_branch
        @object.async_viewer_can_update?(@context[:viewer]).then do |can_update|
          next false unless can_update
          next false unless @object.open?
          @object.async_base_repository.then do |repository|
            repository.async_writable?
          end
        end
      end
    end
  end
end
