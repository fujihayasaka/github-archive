# typed: true
# frozen_string_literal: true

module PullRequests
  # Handles anything complicated in the merge button area of a pull
  # request.
  class MergeButtonView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include CommentsHelper
    include GitHub::Memoizer
    include StatusHelper
    include GitHub::ResilienceMixin
    include Marketplace::Domain::Provider

    # An error raised on an unexpected data edge case.
    class TooManyCommits < StandardError; end

    attr_reader :pull
    attr_reader :merge_type
    attr_reader :commit_title
    attr_reader :commit_message
    attr_reader :gate_requests

    POLLING_INTERVAL = 2000
    POLLING_MULTIPLIER = 2

    def channels
      [
        *GitHub::WebSocket::Channels.pull_request_mergeable(pull),
        GitHub::WebSocket::Channels.pull_request_state(pull),
        GitHub::WebSocket::Channels.pull_request_review_state(pull),
        GitHub::WebSocket::Channels.pull_request_workflow_run_state(pull),
        GitHub::WebSocket::Channels.pull_request_deployed(pull),
        GitHub::WebSocket::Channels.pull_request_merge_queue_entry_state(pull)
      ]
    end

    def show_merge_area?
      pull.open? && !pull.merged?
    end

    def merge_queue_enabled_for_pull_request?
      return @is_merge_queue_enabled_for_pull_request if defined?(@is_merge_queue_enabled_for_pull_request)
      @is_merge_queue_enabled_for_pull_request = pull.merge_queue_enabled?
    end

    def show_merge_queue?
      return false unless merge_queue_enabled_for_pull_request?

      true
    end

    def merge_when_ready_button_disabled?
      state == :unknown || pull.draft?
    end

    def disable_merge_button_polling?
      pull.repository.feature_enabled?(:disable_polling_for_merge_button)
    end

    def polling_interval_override
      if pull.repository.feature_enabled?(:merge_button_polling_backoff)
        4000
      else
        POLLING_INTERVAL
      end
    end

    def polling_multiplier_override
      if pull.repository.feature_enabled?(:merge_button_polling_backoff)
        4
      else
        POLLING_MULTIPLIER
      end
    end

    # Should the "Update branch" button be shown in the merge area for this PR?
    #
    # "Update branch" is only needed when required status checks are enabled for
    # the PR (so that we can be sure the status checks will still be green when
    # the PR is merged).
    #
    # Returns Boolean
    def show_update_branch_button?
      return false if logged_in? && current_user.must_verify_email?

      # A pull request cannot be updated if it has already been enqueued for
      # merge; status checks will be dealt with as the merge queue proceeds.
      return false if pull.in_merge_queue?
      return false unless head_pushable?

      # Show the "Update Branch" if any of the following is true:
      # - The `always show "Update Branch" button regardless of branch protection rules` repository setting
      # - There is a branch protection rule with status checks enabled
      return false unless strict_required_status_checks_enabled? || update_branch_button_always_enabled?
      # In all cases, show the "Update Branch" button only if the head branch is behind the base branch
      pull.behind_base?
    end

    def strict_required_status_checks_enabled?
      policy_evaluator = pull.base_branch_rule_evaluator
      return false unless policy_evaluator.present?
      return false unless policy_evaluator.required_status_checks_enabled?
      return false unless policy_evaluator.strict_required_status_checks_policy?
      policy_evaluator.required_status_checks.any?
    end

    def update_branch_button_always_enabled?
      pull.base_repository.enable_update_branch?
    end

    def default_update_branch_type
      return "is-updating-via-merge" unless pull.repository&.feature_enabled?(:default_to_rebase_for_linear_history)

      if pull.updateability.check_required_linear_history.success?
        "is-updating-via-merge"
      else
        "is-updating-via-rebase"
      end
    end

    def advisory_workspace?
      pull.repository.advisory_workspace?
    end

    def advisory_repository
      pull.repository.parent_advisory_repository
    end

    def repository_advisory
      pull.repository.parent_advisory
    end

    def base_branch_pushable?
      return @base_branch_pushable if defined?(@base_branch_pushable)
      @base_branch_pushable = base_repo_pushable? && authorized_to_update_protected_base_branch?
    end

    def base_repo_pushable?
      return @base_repo_pushable if defined?(@base_repo_pushable)
      @base_repo_pushable = pull.base_repository.pushable_by?(current_user)
    end

    def authorized_to_update_protected_base_branch?
      policy_evaluator = pull.base_branch_rule_evaluator
      return true unless policy_evaluator

      policy_evaluator.authorized?(current_user)
    end

    def enforce_linear_history?
      policy_evaluator = pull.base_branch_rule_evaluator
      return false unless policy_evaluator
      policy_evaluator.required_linear_history_enabled?
    end

    memoize def rule_merge_method_statuses
      policy_evaluator = pull.base_branch_rule_evaluator
      return BranchRuleEvaluator::ALL_MERGE_METHODS_ALLOWED.dup unless policy_evaluator
      policy_evaluator.supported_merge_methods(actor: current_user)
    end

    def head_branch_pushable?
      head_pushable? && authorized_to_update_protected_head_branch?
    end

    def authorized_to_update_protected_head_branch?
      policy_evaluator = pull.head_branch_rule_evaluator
      return true unless policy_evaluator

      policy_evaluator.authorized?(current_user)
    end

    # Public: Returns true if the head ref of the pull request is protected in such a way that would prevent the current
    # user from directly pushing a merge commit. This accounts for locked branches, required status checks, required reviewers, or
    # required linear history, and any available admin overrides.
    #
    # Returns: Boolean
    def protection_prohibits_merge_on_head?
      policy_evaluator = pull.head_branch_rule_evaluator
      return false unless policy_evaluator

      !policy_evaluator.commit_authorized?(current_user) ||
        # Note that "PR only" bypass mode only allows bypass using a PR where the protected branch is the BASE branch
        (!policy_evaluator.can_override_required_linear_history?(actor: current_user, is_pull_request: false) &&
        policy_evaluator.required_linear_history_enabled?)
    end

    def pull_request_reviews_required?
      return false if !pull.base_branch_rule_evaluator || pull_request_enqueued?

      pull.base_branch_rule_evaluator.pull_request_reviews_required? && pull.repository.supports_protected_branches?
    end

    def codeowner_reviews_required?
      return false unless pull.base_branch_rule_evaluator

      pull.base_branch_rule_evaluator.require_code_owner_review?
    end

    def head_pushable?
      pull.head_repository && pull.head_repository.owner && pull.head_repository.pushable_by?(current_user, ref: head_ref)
    end

    def head_ref
      pull.head_ref_name
    end

    def display_head_ref
      head_ref.dup.force_encoding("utf-8").scrub!
    end

    def head_repo
      pull.head_repository
    end

    def head_branch_deleteable?
      pull.head_ref_deleteable_by?(current_user) || pull.head_ref_deleteable_after_updating_dependents?(current_user)
    end

    def head_branch_restoreable?
      pull.head_ref_restorable_by?(current_user)
    end

    def fork_deleteable?
      GitHub.dogstats.time("merge_button_view", tags: ["action:fork_deleteable"]) do
        return false unless head_repo_is_fork?
        return false unless pull.closed?
        return false unless head_repo.adminable_by?(current_user)

        !head_repo_has_activity?
      end
    end

    # Returns one of :unknown, :clean, :dirty, :draft, or :unstable.
    def state
      merge_state.status
    end

    # Returns "pending", "success", "error", "failure", or nil if the head commit has no statuses
    def commit_state
      combined_status.state
    end

    # Return the PullRequest::MergeState for the current viewer
    memoize def merge_state
      with_database_error_fallback(fallback: PullRequest::UnknownMergeState.new(pull, viewer: current_user)) do
        merge_state = pull.cached_merge_state(viewer: current_user)

        # Immediately try to load the status to trigger an error if
        # status is unavailable, e.g. because a DB cluster is unavailable.
        # If that's the case, we want to consistently use a fallback for
        # `MergeState` object.
        merge_state.status

        merge_state
      end
    end

    def combined_status
      if required_status_decision_basis_commit&.sha && required_status_decision_basis_commit.sha == pull.merge_commit_sha
        # In some cases the required status decision was made based on checks
        # associated with the merge commit sha, in this case we
        # should show the checks/statuses for the PR's merge_commit_sha so that it matches
        # other merge box elements.
        pull.build_combined_status_for_sha(pull.merge_commit_sha)
      else
        pull.combined_status
      end
    end

    def required_status_decision_basis_commit
      return @required_status_decision_basis_commit if defined?(@required_status_decision_basis_commit)
      # If we're recalculating the merge commit (state == :unknown) then any decision from branch protections
      # will be made against an outdated commit that will be rewritten anyway so don't bother checking.
      return @required_status_decision_basis_commit = nil if merge_state.unknown?
      return @required_status_decision_basis_commit = nil if merge_state.rules_engine_evaluation_result.rules_fulfilled?

      commits = merge_state.rules_engine_evaluation_result.rule_runs.map(&:basis_commit).compact.uniq
      if commits.size > 1
        # This scenario is unexpected, send a warning so we can debug
        # and just choose an arbitrary commit to return as the basis.
        boom = TooManyCommits.new(commits.map(&:sha).join(" "))
        boom.set_backtrace(caller)
        Failbot.report_trace(boom, "gh.pull_request.id": pull&.id)
      end
      @required_status_decision_basis_commit = commits.first
    end

    def unstable_message
      case
      when base_repo_pushable?
        "Merge with caution!"
      when combined_status.state == "pending"
        "This branch has pending checks, but can be merged."
      else
        "This branch has failed checks, but can be merged."
      end
    end

    def tasks
      @_tasks ||= PullRequest::Tasks.new(pull)
    end

    # Returns the currently selected merge method.
    memoize def merge_method
      with_database_error_fallback(fallback: :merge) do
        pull.default_merge_method_for(current_user)
      end
    end

    def default_commit_title
      @commit_title || (merge_method == :squash ? pull.default_squash_commit_title : pull.default_merge_commit_title)
    end

    def default_commit_message
      @commit_message || (merge_method == :squash ? pull.default_squash_commit_message : pull.default_merge_commit_message)
    end

    def admin_override_possible?
      return @admin_override_possible if defined?(@admin_override_possible)
      @admin_override_possible = merge_state.admin_override_possible?
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Admins must confirm they are bypassing required checks such as
    # failures or missing approvals. This does not apply for
    # `merge_state.blocked_only_by_required_linear_history?` because they
    # haven't merged yet so there is nothing for them to override
    # Returns: Boolean
    def admin_must_confirm?
      admin_override_possible? && !merge_state.blocked_only_by_required_linear_history?
    end

    def disable_auto_merge_form_action
      urls.destroy_auto_merge_request_path(pull.repository.owner, pull.repository, pull.number)
    end

    # Generate CSS classes to be applied to the merge form related to the admin override. These are used to contextually
    # hide and show admin override controls if they only apply to a specific merge method.
    #
    # Returns: String, possibly empty
    def admin_override_classes
      classes = []
      classes << "js-admin-override-merge" if admin_override_possible?
      classes << "js-admin-override-squash" if admin_must_confirm?
      classes << "js-admin-override-rebase" if admin_must_confirm?
      classes.join(" ")
    end

    # Disable the merge button entirely, including the merge method dropdown.
    #
    # Returns: Boolean
    def merge_button_disabled?
      return true if pull.draft?
      merging_blocked_without_override? && !admin_override_possible?
    end

    def show_auto_merge_options?
      return @show_auto_merge_options if defined?(@show_auto_merge_options)
      @show_auto_merge_options = with_database_error_fallback(fallback: false) do
        pull.can_enable_auto_merge(actor: current_user).allowed?
      end
    end

    def show_merge_message?
      (base_branch_pushable? && !advisory_workspace?) || auto_merge_enabled?
    end

    def auto_merge_enabled?
      return @auto_merge_enabled if defined?(@auto_merge_enabled)
      @auto_merge_enabled = pull.auto_merge_request.present?
    end

    def disable_auto_merge_button_disabled?
      !base_branch_pushable? && current_user != pull.user
    end

    def initial_button_class
      return merge_rebase_button_class if merge_method == :rebase
      return merge_squash_button_class if merge_method == :squash
      merge_button_class
    end

    def merge_button_class
      if ([:clean, :has_hooks].include?(state)) && (!merge_state.draft?)
        "btn-primary"
      elsif admin_override_possible?
        "btn-danger"
      else
        ""
      end
    end

    def merge_commit_button_class
      return merge_button_class unless rule_merge_method_statuses[:merge] != :allowed

      if admin_override_possible? || rule_merge_method_statuses[:merge] == :allowed_with_bypass
        "btn-danger"
      else
        ""
      end
    end

    def merge_squash_button_class
      if rule_merge_method_statuses[:squash] == :allowed_with_bypass
        "btn-danger"
      else
        merge_button_class
      end
    end

    def merge_rebase_button_class
      if !pull.rebase_safe?
        ""
      elsif rule_merge_method_statuses[:rebase] == :allowed_with_bypass
        "btn-danger"
      else
        merge_button_class
      end
    end

    # Is the "Create a merge commit" option enabled in the merge method dropdown?
    #
    # Returns: Boolean
    def can_choose_merge_commit?
      case
      when merge_button_disabled? && !show_auto_merge_options?
        false
      when repo_merge_commit_setting.disallowed?
        false
      else
        true
      end
    end

    # Is the "Merge pull request" button enabled once chosen?
    #
    # Returns: Boolean
    alias can_perform_merge_commit? can_choose_merge_commit?

    # Is the "Squash and merge" option enabled in the merge method dropdown?
    #
    # Returns: Boolean
    def can_choose_squash_merge?
      case
      when merge_button_disabled? && !show_auto_merge_options?
        false
      when repo_squash_merge_setting.disallowed?
        false
      else
        true
      end
    end

    # Is the "Squash and merge" button enabled once chosen?
    #
    # Returns: Boolean
    alias can_perform_squash_merge? can_choose_squash_merge?

    # Is the "rebase merge" option enabled in the merge method dropdown?
    #
    # Returns: Boolean
    def can_choose_rebase_merge?
      case
      when merge_button_disabled? && !show_auto_merge_options?
        false
      when repo_rebase_merge_setting.disallowed?
        false
      else
        true
      end
    end

    # Is the "Rebase and merge" button enabled once chosen?
    #
    # Returns: Boolean
    def can_perform_rebase_merge?
      case
      when !can_choose_rebase_merge?
        false
      when !pull.rebase_safe?
        false
      else
        true
      end
    end

    def merge_area_status_class
      return "is-merging-group" if show_merge_queue?

      case merge_method
      when :squash
        "is-squashing"
      when :rebase
        "is-rebasing"
      else
        "is-merging"
      end
    end

    def any_reviews_or_reviewers?
      merge_state.reviews.any? || pull.review_requests.pending.any?
    end

    def requested_changes?
      merge_state.requested_changes?
    end

    def can_add_review?
      current_user != pull.user
    end

    def can_be_quick_approved?(review)
      same_pull?(review) &&
        review.user == current_user &&
        review.changes_requested? &&
        !pull.pending_review_by?(current_user)
    end

    def same_pull?(review)
      pull == review.pull_request
    end

    def review_href(review)
      anchor = "##{comment_dom_id(review)}"

      if same_pull?(review)
        anchor
      else
        pull_request_path = urls.pull_request_path(review.pull_request)
        pull_request_path + anchor
      end
    end

    # Do we care to show review status at all? This is true if the pull request's
    # base branch is protected by reviews, or if the PR has any reviews or reviewers.
    def show_review_status?
      if merge_state.draft?
        any_reviews_or_reviewers?
      else
        pull_request_reviews_required? || any_reviews_or_reviewers? || codeowner_reviews_required?
      end
    end

    def required_review_thread_resolution_enabled?
      return false if !pull.base_branch_rule_evaluator || pull_request_enqueued?

      pull.base_branch_rule_evaluator.required_review_thread_resolution_enabled?
    end

    # Returns the count of unresolved and resolved threads
    def review_thread_counts
      threads = PullRequestReviewThread.non_pending_review_threads(pull.id)
        .includes(:pull_request_review)

      # Not all threads count as conversations. Non conversation threads should not be counted towards the branch protection policy.
      threads = threads.filter(&:conversation?)

      resolved_threads, unresolved_threads = threads.partition { |thread| thread.resolved? }
      [unresolved_threads.length, resolved_threads.length]
    end

    def review_required_as_code_owner?(reviewer)
      return false unless pull.base_branch_rule_evaluator&.require_code_owner_review?

      pull.codeowners.include?(reviewer)
    end

    def conflict_editor_disabled?
      pull.cross_repo? && !GitHub.cross_repo_conflict_editor_enabled?
    end

    def ci_category
      if marketplace_domain.repository_settings.has_docker_file?(pull.repository_id)
        "container-ci"
      elsif marketplace_domain.repository_settings.is_mobile?(pull.repository_id)
        "mobile-ci"
      else
        "continuous-integration"
      end
    end

    # Conflicts are only valid if the mergeable state has also been calculated
    # and set to `false`.
    #
    # Returns a Boolean.
    def show_conflicts?
      pull.conflicted_files.present? && merge_state.mergeable == false
    end

    def show_pull_request_enqueued_component?
      show_merge_queue? && base_branch_pushable? && pull_request_enqueued?
    end

    def rebase_error_text
      if pull.rebase_conflicts?
        "This branch cannot be rebased due to conflicts".freeze
      else
        "There was a problem generating the rebase commit".freeze
      end
    end

    sig { returns(PullRequest::MergeMethodSettings::Value) }
    def repo_merge_commit_setting = repo_allowable_merge_methods.merge_commit

    sig { returns(PullRequest::MergeMethodSettings::Value) }
    def repo_squash_merge_setting = repo_allowable_merge_methods.squash_merge

    sig { returns(PullRequest::MergeMethodSettings::Value) }
    def repo_rebase_merge_setting = repo_allowable_merge_methods.rebase_merge

    private

    def head_repo_is_fork?
      head_repo && head_repo.fork?
    end

    def head_repo_has_activity?
      GitHub.dogstats.time("merge_button_view", tags: ["action:head_repo_has_activity"]) do
        head_repo_has_issues? || head_repo_has_pulls?
      end
    end

    def head_repo_has_pulls?
      head_repo && head_repo.pull_requests.any?
    end

    def head_repo_has_issues?
      head_repo && head_repo.issues.any?
    end

    # Is the state of the PullRequest such that it cannot be merged normally by a user without
    # the admin override option?
    #
    # Returns a Boolean.
    def merging_blocked_without_override?
      ([:draft, :dirty, :blocked, :unknown, :behind].include?(state) || merge_state.draft?)
    end

    def pull_request_enqueued?
      merge_queue_enabled_for_pull_request? && pull.in_merge_queue?
    end

    sig { returns(PullRequest::MergeMethodSettings) }
    memoize def repo_allowable_merge_methods
      pull.async_allowable_merge_methods(actor: current_user).sync
    end
  end
end
