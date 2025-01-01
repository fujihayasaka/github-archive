# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class PullRequestPayload
    extend T::Sig

    class AuthorPayload < T::Struct
      const :login, String
      const :avatarUrl, String
      const :name, String
      const :url, String
    end

    class MergeBoxAliveChannels < T::Struct
      const :stateChannel, String
      const :deployedChannel, String
      const :reviewStateChannel, String
      const :workflowsChannel, String
      const :mergeQueueChannel, String
      const :headRefChannel, String
      const :baseRefChannel, String
      const :commitHeadShaChannel, String
      const :gitMergeStateChannel, String
    end

    class MergeMethod < T::Enum
      enums do
        Merge = new("MERGE")
        Squash = new("SQUASH")
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

    class MergeQueue < T::Struct
      const :url, String
    end

    class MergeQueueEntry < T::Struct
      const :position, T.nilable(Integer)
      const :state, MergeQueueEntryState
    end

    class OpinionatedReviewPayload < T::Struct
      const :authorCanPushToRepository, T::Boolean
      const :author, T.nilable(AuthorPayload)
      const :onBehalfOf, T::Array[String]
      const :state, PullRequestReviewState
    end

    class RepositoryPayload < T::Struct
      const :ownerLogin, T.nilable(String)
      const :name, T.nilable(String)
    end

    class ViewerMergeMethods < T::Struct
      const :isAllowable, T::Boolean
      const :isAllowableWithBypass, T::Boolean
      const :isDefault, T::Boolean
      const :name, MergeMethod
    end

    class ViewerMergeActions < T::Struct
      const :isAllowable, T::Boolean
      const :isAllowableWithBypass, T::Boolean
      const :mergeMethods, T::Array[ViewerMergeMethods]
      const :name, MergeAction
    end

    class PullRequestPayload < T::Struct
      const :autoMergeRequest, T.nilable(AutoMergeRequest)
      const :baseRefName, String
      const :headRefName, String
      const :headRefOid, String
      const :headRepository, T.nilable(RepositoryPayload)
      #global_relay_id
      const :id, String
      const :isDraft, T::Boolean
      const :isInMergeQueue, T::Boolean
      const :latestOpinionatedReviews, T::Array[OpinionatedReviewPayload]
      const :mergeBoxAliveChannels, MergeBoxAliveChannels
      const :mergeQueue, T.nilable(MergeQueue)
      const :mergeQueueEntry, T.nilable(MergeQueueEntry)
      const :mergeStateStatus, MergeStateStatus
      const :numberOfCommits, Numeric
      const :resourcePath, String
      const :state, PullRequestState
      const :viewerCanAddAndRemoveFromMergeQueue, T::Boolean
      const :viewerCanDeleteHeadRef, T::Boolean
      const :viewerCanDisableAutoMerge, T::Boolean
      const :viewerCanEnableAutoMerge, T::Boolean
      const :viewerCanRestoreHeadRef, T::Boolean
      const :viewerCanUpdateBranch, T::Boolean
      const :viewerCanUpdate, T::Boolean
      const :viewerDidAuthor, T::Boolean
      const :viewerMergeActions, T::Array[ViewerMergeActions]
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
        autoMergeRequest: build_auto_merge_request(pull_request_data.auto_merge_request),
        baseRefName: pull_request.base_ref_name,
        headRefOid: T.must(pull_request_data.pull_request.head_sha),
        headRefName: pull_request_data.pull_request.head_ref.dup.force_encoding("utf-8"),
        headRepository: build_head_repository(pull_request_data.head_repository, pull_request_data.head_repository_owner),
        id: pull_request.global_relay_id,
        isDraft: pull_request_data.pull_request.draft_state?,
        isInMergeQueue: pull_request.in_merge_queue?,
        latestOpinionatedReviews: build_latest_opinionated_reviews(pull_request_data.latest_opinionated_reviews),
        mergeBoxAliveChannels: alive_channels(pull_request_data),
        mergeQueue: build_merge_queue(pull_request_data.merge_queue),
        mergeQueueEntry: build_merge_queue_entry(pull_request_data.merge_queue_entry),
        mergeStateStatus: MergeStateStatus.deserialize(pull_request_data.merge_state.to_s.upcase),
        numberOfCommits: pull_request_data.total_commits,
        resourcePath: T.must(pull_request_data.pull_request.url),
        state: PullRequestState.deserialize(pull_request.state&.to_s&.upcase),
        viewerCanAddAndRemoveFromMergeQueue: pull_request_data.viewer_can_add_and_remove_from_merge_queue,
        viewerCanDeleteHeadRef: pull_request_data.viewer_can_delete_head_ref,
        viewerCanDisableAutoMerge: pull_request_data.viewer_can_disable_auto_merge,
        viewerCanEnableAutoMerge: pull_request_data.viewer_can_enable_auto_merge,
        viewerCanRestoreHeadRef: pull_request_data.viewer_can_restore_head_ref,
        viewerCanUpdate: pull_request_data.viewer_can_update,
        viewerCanUpdateBranch: pull_request_data.viewer_can_update_branch,
        viewerDidAuthor: pull_request_data.viewer_did_author,
        viewerMergeActions: evaluated_allowable_merge_actions(pull_request_data.allowable_merge_actions),
      )
    end

    sig { params(auto_merge_request: T.nilable(::AutoMergeRequest)).returns(T.nilable(AutoMergeRequest)) }
    def build_auto_merge_request(auto_merge_request)
      if auto_merge_request
        AutoMergeRequest.new(mergeMethod: MergeMethod.deserialize(auto_merge_request.minimal_merge_method.to_s.upcase))
      end
    end

    sig { params(head_repository: T.nilable(Repository), head_repository_owner: T.nilable(User)).returns(T.nilable(RepositoryPayload)) }
    def build_head_repository(head_repository, head_repository_owner)
      if head_repository && head_repository_owner
        RepositoryPayload.new(name: head_repository.name, ownerLogin: head_repository_owner.display_login)
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
        headRefChannel: GitHub::WebSocket::Channels.signed_branch(pull_request_data.head_repository, pull_request.display_head_ref_name),
        baseRefChannel: GitHub::WebSocket::Channels.signed_branch(pull_request_data.base_repository, pull_request.display_base_ref_name),
        commitHeadShaChannel: GitHub::WebSocket::Channels.signed_commit(pull_request_data.base_repository, pull_request.head_sha),
        gitMergeStateChannel: GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(pull_request)
      )
    end

    sig { params(latest_opinionated_reviews: T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::OpinionatedReview]).returns(T::Array[OpinionatedReviewPayload]) }
    def build_latest_opinionated_reviews(latest_opinionated_reviews)
      latest_opinionated_reviews.map do |review|
        author = review.author
        OpinionatedReviewPayload.new(
          authorCanPushToRepository: review.author_can_push_to_repository,
          onBehalfOf: review.on_behalf_of.map(&:name).compact,
          author: if author
                    AuthorPayload.new(
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

    sig { params(allowable_merge_actions: T::Array[PullRequests::PageData::MergeBox::PullRequestLoader::AllowableMergeAction]).returns(T::Array[ViewerMergeActions]) }
    def evaluated_allowable_merge_actions(allowable_merge_actions)
      allowable_merge_actions.map do |merge_action|
        ViewerMergeActions.new(
          isAllowable: merge_action.is_allowable,
          isAllowableWithBypass:  merge_action.is_allowable_with_bypass,
          name: MergeAction.deserialize(merge_action.name.to_s.upcase),
          mergeMethods: evaluate_allowable_merge_methods(merge_action.merge_methods),
        )
      end
    end

    sig { params(merge_methods: T::Array[PullRequest::AllowableMergeMethod]).returns(T::Array[ViewerMergeMethods]) }
    def evaluate_allowable_merge_methods(merge_methods)
      merge_methods.map do |merge_method|
        ViewerMergeMethods.new(
          isAllowable: merge_method.is_allowable,
          isAllowableWithBypass: merge_method.is_allowable_with_bypass,
          name: MergeMethod.deserialize(merge_method.name.to_s.upcase),
          isDefault: merge_method.is_default
        )
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
        MergeQueueEntry.new(position: merge_queue_entry.position, state: MergeQueueEntryState.deserialize(merge_queue_entry.state.upcase.to_s))
      end
    end
  end
end
