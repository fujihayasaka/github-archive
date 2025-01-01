# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class PullRequestLoader
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    class OpinionatedReview < T::Struct
      const :id, Integer
      const :author_can_push_to_repository, T::Boolean
      const :on_behalf_of, T::Array[Team]
      const :author, T.nilable(User)
      const :state, Integer
    end

    class PendingReviewRequest < T::Struct
      const :reviewer, T.any(T.nilable(User), T.nilable(Team))
      const :is_code_owner, T::Boolean
    end

    class AllowableMergeAction < T::Struct
      const :name, Symbol
      const :is_allowable, T::Boolean
      const :is_allowable_with_bypass, T::Boolean
      const :merge_methods, T::Array[::PullRequest::AllowableMergeMethod]
    end

    class PullRequestData < T::Struct
      const :allowable_merge_actions, T::Array[AllowableMergeAction]
      const :auto_merge_request, T.nilable(::AutoMergeRequest)
      const :base_repository, Repository
      const :pull_request, PullRequest
      const :head_repository,  T.nilable(Repository)
      const :head_repository_owner,  T.nilable(User)
      const :merge_queue,  T.nilable(::MergeQueue)
      const :merge_queue_entry, T.nilable(::MergeQueueEntry)
      const :merge_state, Symbol
      const :latest_opinionated_reviews, T::Array[OpinionatedReview]
      const :pending_review_requests, T::Array[PendingReviewRequest]
      const :total_commits, Numeric
      const :viewer_can_add_and_remove_from_merge_queue, T::Boolean
      const :viewer_can_add_to_merge_queue_solo, T::Boolean
      const :viewer_did_author, T::Boolean
      const :viewer_can_delete_head_ref, T::Boolean
      const :viewer_can_update_branch, T::Boolean
      const :viewer_can_update, T::Boolean
      const :viewer_can_restore_head_ref, T::Boolean
      const :viewer_can_enable_auto_merge, T::Boolean
      const :viewer_can_disable_auto_merge, T::Boolean
      const :viewer_can_dismiss_reviews, T::Boolean
      const :viewer_can_re_request_reviews, T::Boolean
      const :viewer_can_admin_bypass_merge_requirements, T::Boolean
    end

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
      ).returns(PullRequestData)
    end
    def self.load(current_user:, pull_request:)
      new(current_user:, pull_request:).load
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(User)).void }
    def initialize(pull_request:, current_user:)
      @pull_request = pull_request
      @current_user = current_user
    end

    sig { returns(PullRequestData) }
    def load
      PullRequestData.new(
        allowable_merge_actions: allowable_merge_actions,
        auto_merge_request: pull_request.auto_merge_request,
        base_repository: base_repository,
        pull_request: pull_request,
        head_repository: head_repository,
        head_repository_owner: head_repository&.owner,
        merge_queue: merge_queue,
        merge_queue_entry: merge_queue_entry,
        merge_state: merge_state_status,
        latest_opinionated_reviews: latest_opinionated_reviews,
        pending_review_requests: pending_review_requests,
        total_commits: with_database_error_fallback(fallback: 0) { pull_request.total_commits },
        viewer_can_add_and_remove_from_merge_queue: with_database_error_fallback(fallback: false) { pull_request.async_can_add_to_merge_queue?(current_user).sync },
        viewer_can_add_to_merge_queue_solo: viewer_can_add_to_merge_queue_solo?,
        viewer_did_author: viewer_did_author?,
        viewer_can_delete_head_ref: viewer_can_delete_head_ref?,
        viewer_can_disable_auto_merge: with_database_error_fallback(fallback: false) { pull_request.can_disable_auto_merge?(actor: current_user) },
        viewer_can_enable_auto_merge: with_database_error_fallback(fallback: false) { pull_request.can_enable_auto_merge(actor: current_user).allowed? },
        viewer_can_restore_head_ref: with_database_error_fallback(fallback: false) { pull_request.head_ref_restorable_by?(current_user) },
        viewer_can_update: with_database_error_fallback(fallback: false) { pull_request.async_viewer_can_update?(current_user).sync },
        viewer_can_update_branch: with_database_error_fallback(fallback: false) { pull_request.async_branch_is_updatable_by?(current_user).sync },
        viewer_can_dismiss_reviews: with_database_error_fallback(fallback: false) { viewer_can_dismiss_reviews },
        viewer_can_re_request_reviews: with_database_error_fallback(fallback: false) { pull_request.can_re_request_review?(current_user) },
        viewer_can_admin_bypass_merge_requirements: viewer_can_admin_bypass_merge_requirements?
      )
    end

    sig { returns(T.nilable(Repository)) }
    memoize def head_repository
      pull_request.head_repository
    end

    sig { returns(Repository) }
    memoize def base_repository
      T.must(pull_request.base_repository)
    end

    sig { returns(T.nilable(::MergeQueue)) }
    memoize def merge_queue
      pull_request.merge_queue
    end

    sig { returns(T.nilable(::MergeQueueEntry)) }
    memoize def merge_queue_entry
      merge_queue&.entry_for(pull_request: pull_request)
    end

    sig { returns(T::Array[OpinionatedReview]) }
    def latest_opinionated_reviews
      reviews = with_database_error_fallback(fallback: []) do
        if T.must(@current_user).feature_enabled?(:latest_opinionated_reviews_cross_repo_batch)
          pull_request.async_latest_enforced_reviews_candidate(writers_only: false).sync
        else
          pull_request.latest_enforced_reviews(writers_only: false)
        end
      end
      reviews.reject { |review| review.hide_from_user?(current_user) }

      reviews.map do |review|
        OpinionatedReview.new(
          id: review.id,
          author_can_push_to_repository: review.async_author_can_push_to_repository?.sync,
          on_behalf_of: review.prelude_on_behalf_of_visible_teams_for(current_user).sort_by(&:created_at),
          author: review.user,
          # This is an enum
          state: review.state
        )
      end
    end

    sig { returns(T::Array[PendingReviewRequest]) }
    def pending_review_requests
      with_database_error_fallback(fallback: []) do
        pull_request
        .review_requests_pending
        .reject { |review| review.hide_from_user?(current_user) }
        .map do |review|
          PendingReviewRequest.new(
            reviewer: review.reviewer,
            is_code_owner: review.async_as_codeowner?.sync
          )
        end
      end
    end

    sig { returns(T::Array[AllowableMergeAction]) }
    def allowable_merge_actions
      ::PullRequest::AllowableMergeAction.for(pull_request: pull_request, viewer: T.must(current_user)).then do |actions|
        actions.map do |action|
          AllowableMergeAction.new(
            name: action.name,
            is_allowable: action.is_allowable,
            is_allowable_with_bypass: action.is_allowable_with_bypass,
            merge_methods: action.merge_methods.sync
          )
        end
      end.sync
    end

    sig { returns(PullRequest::MergeState) }
    memoize def merge_state
      pull_request.cached_merge_state(viewer: current_user)
    end

    # Return values can be :behind, :blocked, :clean, :dirty, :has_hooks, :unknown, :unstable.
    # In the interest of minimizing the blast radius of changing the types everywhere, just note the return types for now.
    sig { returns(Symbol) }
    memoize def merge_state_status
      with_database_error_fallback(fallback: :unknown) do
        merge_state.status
      end
    end

    sig { returns(T::Boolean) }
    def viewer_did_author?
      pull_request.user_id == T.must(current_user).id
    end

    sig { returns(T::Boolean) }
    def viewer_can_add_to_merge_queue_solo?
      with_database_error_fallback(fallback: false) do
        return false if !merge_queue&.requires_deployments_before_merging?

        pull_request.can_add_to_merge_queue_solo?(current_user)
      end
    end

    sig { returns(T::Boolean) }
    def viewer_can_delete_head_ref?
      deletable = with_database_error_fallback(fallback: false) do
        pull_request.head_ref_deleteable_by?(current_user)
      end
      return true if deletable
      with_database_error_fallback(fallback: false) do
        pull_request.head_ref_deleteable_after_updating_dependents?(current_user)
      end
    end

    sig { returns(T::Boolean) }
    def viewer_can_dismiss_reviews
      if pull_request.base_branch_rule_evaluator && pull_request.base_branch_rule_evaluator&.restricted_dismissed_reviews?
        T.must(pull_request.base_branch_rule_evaluator).review_dismissable_by?(current_user)
      else
        T.must(pull_request.repository).pushable_by?(current_user)
      end
    end

    sig { returns(T::Boolean) }
    def viewer_can_admin_bypass_merge_requirements?
      with_database_error_fallback(fallback: false) do
        if base_repository.feature_enabled_for_source?(:new_merge_box_bypass_linear_history)
          # This method should only return true when rules are failing but can be bypassed
          # PR merges will always be blocked by required linear history, but it only matters for actual bypass when the merge method is merge
          # Therefore, allow bypassing rules when the merge type is merge but the only rule failing is linear history
          merge_state.admin_override_possible? && (merge_state.merge_method == :merge || !merge_state.blocked_only_by_required_linear_history?)
        else
          merge_state.admin_override_possible? && !merge_state.blocked_only_by_required_linear_history?
        end
      end
    end
  end
end
