# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class PullRequestPayload

    class ReviewerType < T::Enum
      enums do
        Team = new("TEAM")
        User = new("USER")
      end
    end

    class Author < T::Struct
      const :login, String
      const :avatarUrl, String
      const :name, String
      const :url, String
    end

    class Reviewer < T::Struct
      const :login, String
      const :avatarUrl, String
      const :name, String
      const :url, String
      const :type, ReviewerType
    end

    class MergeBoxAliveChannels < T::Struct
      const :stateChannel, String
      const :deployedChannel, String
      const :reviewStateChannel, String
      const :workflowsChannel, String
      const :mergeQueueChannel, String
      const :headRefChannel, T.nilable(String)
      const :baseRefChannel, String
      const :gitMergeStateChannel, String
      const :pullRequestChannel, String
    end

    class MergeMethod < T::Enum
      enums do
        Merge = new("MERGE")
        Squash = new("SQUASH")
        Rebase = new("REBASE")
      end
    end

    class UpdateMethod < T::Enum
      enums do
        Merge = new("MERGE")
        Rebase = new("REBASE")
      end
    end

    class AutoMergeRequest < T::Struct
      const :mergeMethod, MergeMethod
    end

    class MergeAction < T::Enum
      enums do
        DirectMerge = new("DIRECT_MERGE")
        MergeQueue = new("MERGE_QUEUE")
      end
    end

    class MergeStateStatus < T::Enum
      enums do
        Behind = new("BEHIND")
        Blocked = new("BLOCKED")
        Clean = new("CLEAN")
        Dirty = new("DIRTY")
        Draft = new("DRAFT")
        HasHooks = new("HAS_HOOKS")
        Unknown = new("UNKNOWN")
        Unstable = new("UNSTABLE")
      end
    end

    class MergeQueueEntryState < T::Enum
      enums do
        AwaitingChecks = new("AWAITING_CHECKS")
        Waiting = new("WAITING")
        Mergeable = new("MERGEABLE")
        Queued = new("QUEUED")
        Unmergeable = new("UNMERGEABLE")
      end
    end

    class PullRequestState < T::Enum
      enums do
        Open = new("OPEN")
        Merged = new("MERGED")
        Closed = new("CLOSED")
      end
    end

    class PullRequestReviewState < T::Enum
      enums do
        Pending = new("PENDING")
        Commented = new("COMMENTED")
        Approved = new("APPROVED")
        ChangesRequested = new("CHANGES_REQUESTED")
        Dismissed = new("DISMISSED")
      end
    end

    class PullRequestMergeMethodStatus < T::Enum
      enums do
        Allowed = new("ALLOWED")
        Blocked = new("BLOCKED")
        AllowedWithBypass = new("ALLOWED_WITH_BYPASS")
        Unavailable = new("UNAVAILABLE")
      end
    end

    class MergeBoxUserPreferences < T::Struct
      const :statusChecksGrouping, String
    end

    class MergeQueue < T::Struct
      const :url, String
    end

    class MergeQueueEntry < T::Struct
      const :position, T.nilable(Integer)
      const :state, MergeQueueEntryState
      const :isLocked, T::Boolean
    end

    class OpinionatedReview < T::Struct
      const :id, Integer
      const :authorCanPushToRepository, T::Boolean
      const :author, T.nilable(Author)
      const :onBehalfOf, T::Array[String]
      const :state, PullRequestReviewState
    end

    class PendingReviewRequest < T::Struct
      const :reviewer, T.nilable(Reviewer)
      const :isCodeOwner, T::Boolean
    end

    class Repository < T::Struct
      const :ownerLogin, T.nilable(String)
      const :name, T.nilable(String)
      const :url, T.nilable(String)
    end

    class ViewerMergeMethods < T::Struct
      const :allowableStatus, PullRequestMergeMethodStatus
      const :isDefault, T::Boolean
      const :name, MergeMethod
    end

    class ViewerMergeActions < T::Struct
      const :allowableStatus, PullRequestMergeMethodStatus
      const :mergeMethods, T::Array[ViewerMergeMethods]
      const :name, MergeAction
    end

    class ViewerUpdateMethods < T::Struct
      const :allowableStatus, PullRequestMergeMethodStatus
      const :isDefault, T::Boolean
      const :name, UpdateMethod
      const :failureReason, T.nilable(String)
    end

    class AdvisoryWorkspace < T::Struct
      const :advisoryWorkspaceId, T.nilable(String)
      const :advisoryWorkspacePath, T.nilable(String)
    end

    class DeprovisionableCodespaces < T::Struct
      const :count, Integer
      const :repositoryCodespacePath, String
    end

    class PullRequestPayload < T::Struct
      const :advisoryWorkspace, T.nilable(AdvisoryWorkspace)
      const :autoMergeRequest, T.nilable(AutoMergeRequest)
      const :baseRefName, String
      const :deprovisionableCodespaces, T.nilable(DeprovisionableCodespaces)
      const :headRefName, String
      const :headRefOid, String
      const :headRepository, T.nilable(Repository)
      const :baseRepository, Repository
      #global_relay_id
      const :id, String
      const :isDraft, T::Boolean
      const :isInMergeQueue, T::Boolean
      const :isCrossRepo, T::Boolean
      const :latestOpinionatedReviews, T::Array[OpinionatedReview]
      const :mergeBoxAliveChannels, MergeBoxAliveChannels
      const :mergeBoxUserPreferences, T.nilable(MergeBoxUserPreferences)
      const :mergeQueue, T.nilable(MergeQueue)
      const :mergeQueueEntry, T.nilable(MergeQueueEntry)
      const :mergeStateStatus, MergeStateStatus
      const :numberOfCommits, Numeric
      const :pendingReviewRequests, T::Array[PendingReviewRequest]
      const :resourcePath, String
      const :state, PullRequestState
      const :viewerCanAddAndRemoveFromMergeQueue, T::Boolean
      const :viewerCanAdminBypassMergeRequirements, T::Boolean
      const :viewerCanAddToMergeQueueSolo, T::Boolean
      const :viewerCanDeleteHeadRef, T::Boolean
      const :viewerCanDisableAutoMerge, T::Boolean
      const :viewerCanEnableAutoMerge, T::Boolean
      const :viewerCanRestoreHeadRef, T::Boolean
      const :viewerCanUpdateBranch, T::Boolean
      const :viewerCanUpdate, T::Boolean
      const :viewerDidAuthor, T::Boolean
      const :viewerMergeActions, T::Array[ViewerMergeActions]
      const :viewerCanDismissReviews, T::Boolean
      const :viewerCanReRequestReviews, T::Boolean
      const :viewerUpdateMethods, T.nilable(T::Array[ViewerUpdateMethods])
    end

    sig do
      params(
        pull_request_data: PullRequestLoader::PullRequestData
      ).returns(PullRequestPayload)
    end
    def self.call(pull_request_data)
      new.call(pull_request_data)
    end

    sig { params(pull_request_data: PullRequestLoader::PullRequestData).returns(PullRequestPayload) }
    def call(pull_request_data)
      pull_request = pull_request_data.pull_request
      PullRequestPayload.new(
        advisoryWorkspace: build_advisory_workspace(pull_request_data),
        autoMergeRequest: build_auto_merge_request(pull_request_data.auto_merge_request),
        baseRefName: pull_request.base_ref_name,
        deprovisionableCodespaces: build_codespace(pull_request_data.deprovisionable_codespaces, pull_request),
        headRefOid: pull_request_data.pull_request.head_sha,
        headRefName: pull_request_data.pull_request.head_ref.dup.force_encoding("utf-8"),
        headRepository: build_repository(pull_request_data.head_repository, pull_request_data.head_repository_owner),
        baseRepository: T.must(build_repository(pull_request_data.base_repository, pull_request_data.base_repository_owner)),
        id: pull_request.global_relay_id,
        isCrossRepo: pull_request_data.pull_request.cross_repo?,
        isDraft: pull_request_data.pull_request.draft?,
        isInMergeQueue: pull_request.in_merge_queue?,
        latestOpinionatedReviews: build_latest_opinionated_reviews(pull_request_data.latest_opinionated_reviews),
        mergeBoxAliveChannels: alive_channels(pull_request_data),
        mergeBoxUserPreferences: pull_request_data.merge_box_user_preferences ? build_merge_box_user_preferences(pull_request_data.merge_box_user_preferences) : nil,
        mergeQueue: build_merge_queue(pull_request_data.merge_queue),
        mergeQueueEntry: build_merge_queue_entry(pull_request_data.merge_queue_entry),
        mergeStateStatus: MergeStateStatus.deserialize(pull_request_data.merge_state.to_s.upcase),
        numberOfCommits: pull_request_data.total_commits,
        pendingReviewRequests: build_pending_review_requests(pull_request_data.pending_review_requests),
        resourcePath: T.must(pull_request_data.pull_request.url),
        state: PullRequestState.deserialize(pull_request.state&.to_s&.upcase),
        viewerCanAddAndRemoveFromMergeQueue: pull_request_data.viewer_can_add_and_remove_from_merge_queue,
        viewerCanAdminBypassMergeRequirements: pull_request_data.viewer_can_admin_bypass_merge_requirements,
        viewerCanAddToMergeQueueSolo: pull_request_data.viewer_can_add_to_merge_queue_solo,
        viewerCanDeleteHeadRef: pull_request_data.viewer_can_delete_head_ref,
        viewerCanDisableAutoMerge: pull_request_data.viewer_can_disable_auto_merge,
        viewerCanEnableAutoMerge: pull_request_data.viewer_can_enable_auto_merge,
        viewerCanRestoreHeadRef: pull_request_data.viewer_can_restore_head_ref,
        viewerCanUpdate: pull_request_data.viewer_can_update,
        viewerCanUpdateBranch: pull_request_data.viewer_can_update_branch,
        viewerDidAuthor: pull_request_data.viewer_did_author,
        viewerMergeActions: evaluated_allowable_merge_actions(pull_request_data.allowable_merge_actions),
        viewerCanDismissReviews: pull_request_data.viewer_can_dismiss_reviews,
        viewerCanReRequestReviews: pull_request_data.viewer_can_re_request_reviews,
        viewerUpdateMethods: evaluate_allowable_update_methods(pull_request_data.allowable_update_methods)
      )
    end

    sig { params(merge_box_user_preferences: T.nilable(PullRequests::PageData::MergeBox::PullRequestLoader::MergeBoxUserPreferences)).returns(T.nilable(MergeBoxUserPreferences)) }
    def build_merge_box_user_preferences(merge_box_user_preferences)
      if merge_box_user_preferences
        MergeBoxUserPreferences.new(
          statusChecksGrouping: merge_box_user_preferences.status_checks_grouping
        )
      end
    end

    sig { params(repository_advisory: T.nilable(RepositoryAdvisory)).returns(T.nilable(String)) }
    def gh_repository_advisory_path(repository_advisory)
      return nil if !repository_advisory
      "/#{repository_advisory.repository&.name_with_display_owner}/security/advisories/#{repository_advisory.ghsa_id}"
    end

    sig { params(pull_request_data: PullRequestLoader::PullRequestData).returns(T.nilable(AdvisoryWorkspace)) }
    def build_advisory_workspace(pull_request_data)
      if pull_request_data.advisory_workspace
        AdvisoryWorkspace.new(
          advisoryWorkspaceId: pull_request_data.advisory_workspace&.ghsa_id,
          advisoryWorkspacePath: gh_repository_advisory_path(pull_request_data.advisory_workspace)
        )
      end
    end

    sig { params(auto_merge_request: T.nilable(::AutoMergeRequest)).returns(T.nilable(AutoMergeRequest)) }
    def build_auto_merge_request(auto_merge_request)
      if auto_merge_request
        AutoMergeRequest.new(mergeMethod: MergeMethod.deserialize(auto_merge_request.minimal_merge_method.to_s.upcase))
      end
    end

    sig { params(codespaces: T.untyped, pull_request: PullRequest).returns(T.nilable(DeprovisionableCodespaces)) }
    def build_codespace(codespaces, pull_request)
      if codespaces.any? && pull_request
        repository = pull_request.repository
        DeprovisionableCodespaces.new(count: codespaces.count, repositoryCodespacePath: "/#{repository&.name_with_display_owner}/codespaces")
      end
    end

    sig { params(repository: T.nilable(::Repository), repository_owner: T.nilable(User)).returns(T.nilable(Repository)) }
    def build_repository(repository, repository_owner)
      if repository && repository_owner
        Repository.new(name: repository.name, ownerLogin: repository_owner.display_login, url: repository.permalink)
      end
    end

    sig { params(pull_request_data: PullRequestLoader::PullRequestData).returns(MergeBoxAliveChannels) }
    def alive_channels(pull_request_data)
      pull_request = pull_request_data.pull_request
      MergeBoxAliveChannels.new(
        stateChannel: GitHub::WebSocket::Channels.signed_pull_request_state(pull_request),
        deployedChannel: GitHub::WebSocket::Channels.signed_pull_request_deployed(pull_request),
        reviewStateChannel: GitHub::WebSocket::Channels.signed_pull_request_review_state(pull_request),
        workflowsChannel: GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(pull_request),
        mergeQueueChannel:  GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(pull_request),
        headRefChannel: pull_request_data.head_repository ? GitHub::WebSocket::Channels.signed_branch(pull_request_data.head_repository, pull_request.display_head_ref_name) : nil,
        baseRefChannel: GitHub::WebSocket::Channels.signed_branch(pull_request_data.base_repository, pull_request.display_base_ref_name),
        gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(pull_request),
        pullRequestChannel: GitHub::WebSocket::Channels.signed_pull_request(pull_request)
      )
    end

    sig { params(latest_opinionated_reviews: T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::OpinionatedReview]).returns(T::Array[OpinionatedReview]) }
    def build_latest_opinionated_reviews(latest_opinionated_reviews)
      latest_opinionated_reviews.map do |review|
        author = review.author
        OpinionatedReview.new(
          id: review.id,
          authorCanPushToRepository: review.author_can_push_to_repository,
          onBehalfOf: review.on_behalf_of.map(&:name).compact,
          author: if author
                    Author.new(
                      login: author.display_login,
                      avatarUrl: author.primary_avatar_url,
                      name: author.name,
                      url: author.permalink
                    )
                  else
                    nil
                  end,
          state: PullRequestReviewState.deserialize(::PullRequestReview.state_name(review.state)&.upcase.to_s)

        )
      end
    end

    sig { params(pending_review_requests: T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::PendingReviewRequest]).returns(T::Array[PendingReviewRequest]) }
    def build_pending_review_requests(pending_review_requests)
      pending_review_requests.map do |review_request|
        reviewer = review_request.reviewer
        PendingReviewRequest.new(
          reviewer: if reviewer
                      Reviewer.new(
                        login: reviewer.is_a?(Team) ? reviewer.name_with_display_owner : reviewer.display_login,
                        avatarUrl: reviewer.primary_avatar_url,
                        name: reviewer.name,
                        url: reviewer.permalink,
                        type: reviewer.is_a?(Team) ? ReviewerType::Team : ReviewerType::User
                      )
                    else
                      nil
                    end,
          isCodeOwner: review_request.is_code_owner
        )
      end.sort_by { |request| request.reviewer&.type.to_s }
    end

    sig { params(allowable_merge_actions: T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::AllowableMergeAction]).returns(T::Array[ViewerMergeActions]) }
    def evaluated_allowable_merge_actions(allowable_merge_actions)
      allowable_merge_actions.map do |merge_action|
        ViewerMergeActions.new(
          allowableStatus: PullRequestMergeMethodStatus.deserialize(merge_action.allowable_status.to_s.upcase),
          name: MergeAction.deserialize(merge_action.name.to_s.upcase),
          mergeMethods: evaluate_allowable_merge_methods(merge_action.merge_methods),
        )
      end
    end

    sig { params(merge_methods: T::Array[PullRequest::AllowableMergeMethod]).returns(T::Array[ViewerMergeMethods]) }
    def evaluate_allowable_merge_methods(merge_methods)
      merge_methods.map do |merge_method|
        ViewerMergeMethods.new(
          allowableStatus: PullRequestMergeMethodStatus.deserialize(merge_method.allowable_status.to_s.upcase),
          name: MergeMethod.deserialize(merge_method.name.to_s.upcase),
          isDefault: merge_method.is_default
        )
      end
    end

    sig { params(update_methods: T.nilable(T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::AllowableUpdateMethod])).returns(T.nilable(T::Array[ViewerUpdateMethods])) }
    def evaluate_allowable_update_methods(update_methods)
      if update_methods
        update_methods.map do |update_method|
          ViewerUpdateMethods.new(
            allowableStatus: PullRequestMergeMethodStatus.deserialize(update_method.allowable_status.to_s.upcase),
            name: UpdateMethod.deserialize(update_method.name.to_s.upcase),
            isDefault: update_method.is_default,
            failureReason: update_method.failure_reason
          )
        end
      end
    end

    sig { params(merge_queue: T.nilable(::MergeQueue)).returns(T.nilable(MergeQueue)) }
    def build_merge_queue(merge_queue)
      if merge_queue
        full_uri = Addressable::URI.parse(merge_queue.async_path_uri.sync)
        permalink = "#{GitHub.url}#{full_uri.path}"
        MergeQueue.new(url: permalink)
      end
    end

    sig { params(merge_queue_entry: T.nilable(::MergeQueueEntry)).returns(T.nilable(MergeQueueEntry)) }
    def build_merge_queue_entry(merge_queue_entry)
      if merge_queue_entry
        MergeQueueEntry.new(
          position: merge_queue_entry.position,
          state: MergeQueueEntryState.deserialize(merge_queue_entry.state.upcase.to_s),
          isLocked: merge_queue_entry.locked?)
      end
    end
  end
end
