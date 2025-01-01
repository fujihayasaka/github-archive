# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestMergeConflictState < MergeConditions::BaseMergeCondition
  include GitHub::Memoizer

  MERGE_CONFLICT_MESSAGE = "Pull request cannot be merged because it has a merge conflict."
  REBASE_CONFLICT_MESSAGE = "Pull request cannot be merged via rebase because it has a rebase conflict."

  def display_name
    "Pull request merge conflict state"
  end

  def description
    "The pull request must not have any unresolved merge conflicts"
  end

  def message
    evaluation_result.errors.first
  end

  sig { override.returns(PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload) }
  def condition_payload
    PullRequests::PageData::MergeBox::MergeRequirementsPayload::ConflictMergeConditionPayload.new(
      type: merge_condition_type,
      displayName: display_name,
      description: description,
      message: message,
      result:  PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionResult.deserialize(result.to_s.upcase),
      conflicts: conflicts&.filenames,
      # Deprecated - leave for backwards compatibility during deploy and remove in follow up PR
      isConflictResolvableInWeb: conflicts&.resolvable?,
      # New fields to use
      webEditorConflictResolution:  web_editor_conflict_resolution,
    )
  end

  def web_editor_conflict_resolution
    return nil unless conflicts.present?

    result = viewer_can_resolve_conflict_result
    PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConflictWebEditorResolution.new(
      viewerCanResolve: result.viewer_can_resolve_on_web,
      viewerCannotResolve:
        case result
        when CannotResolveConflictResult
          PullRequests::PageData::MergeBox::MergeRequirementsPayload::ViewerCannotResolve.new(
          reason: result.viewer_cannot_resolve_reason,
          message: result.viewer_cannot_resolve_message,
        )
        when CanResolveConflictResult
          nil
        else
          T.absurd(result)
        end
    )
  end

  sig { returns(PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType) }
  def merge_condition_type
    begin
      PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType.deserialize(self.class.name&.demodulize&.underscore&.upcase)
    rescue
      PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType.deserialize("UNKNOWN")
    end
  end

  class CannotResolveConflictResult < T::Struct
    const :viewer_cannot_resolve_reason, PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason
    const :viewer_cannot_resolve_message, String

    sig { returns(FalseClass) }
    def viewer_can_resolve_on_web = false
  end

  class CanResolveConflictResult < T::Struct
    sig { returns(TrueClass) }
    def viewer_can_resolve_on_web = true
  end

  sig { returns(T.any(CanResolveConflictResult, CannotResolveConflictResult)) }
  memoize def viewer_can_resolve_conflict_result
    if user_cannot_push_to_head_branch?
      CannotResolveConflictResult.new(
        viewer_cannot_resolve_reason: PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::InsufficientAccess,
        viewer_cannot_resolve_message: "You do not have permission to push to the head branch."
      )
    elsif !pull_request.conflict_resolvable?
      CannotResolveConflictResult.new(
        viewer_cannot_resolve_reason: PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::TooComplex,
        viewer_cannot_resolve_message: "These conflicts are too complex to resolve in the web editor."
      )
    elsif protection_prohibits_merge_on_head?
      CannotResolveConflictResult.new(
        viewer_cannot_resolve_reason: PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::HeadBranchProtected,
        viewer_cannot_resolve_message: "#{pull_request.display_head_ref_name} is a protected branch."
      )
    elsif conflict_editor_disabled?
      CannotResolveConflictResult.new(
        viewer_cannot_resolve_reason: PullRequests::PageData::MergeBox::MergeRequirementsPayload::CannotResolveConflictsReason::AdminDisabled,
        viewer_cannot_resolve_message: "Web conflict resolution across forked repositories has been disabled by your site administrator."
      )
    else
      CanResolveConflictResult.new
    end
  end

  def async_condition
    async_load_conflicts.then do |conflicts|
      unless user.feature_flag_enabled_or_raise?(:skip_enqueue_mergable_update) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @pull_request.enqueue_mergeable_update
      end
      next if !conflicts


      # Rebase conflicts are only blocking if the selected merge method is rebase.
      # Merge conflicts are blocking for all types of merges (merge, squash, and rebase).
      # See https://github.com/github/github/blob/307d3c9c00592cc90c58c18db7e2eb7063f1f7c1/packages/pull_requests/app/controllers/pull_requests/page_data/mutations_controller.rb#L190
      has_merge_conflict = conflicts.conflict_type == "merge_conflict"
      has_rebase_conflict = @merge_method == :rebase && conflicts.conflict_type == "rebase_conflict"

      if has_merge_conflict
        evaluation_result.errors << MERGE_CONFLICT_MESSAGE
      elsif has_rebase_conflict
        evaluation_result.errors << REBASE_CONFLICT_MESSAGE
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def user_cannot_push_to_head_branch?
    !user_allowed_to_push_to_head_branch?
  end

  sig { returns(T::Boolean) }
  def user_allowed_to_push_to_head_branch?
    head_pushable_by_user? && authorized_to_update_protected_head_branch?
  end

  sig { returns(T::Boolean) }
  def head_pushable_by_user?
    return false if pull_request.head_repository.nil? || pull_request.head_repository&.owner.nil?

    pull_request.head_repository&.pushable_by?(user, ref: pull_request.head_ref_name)
  end

  sig { returns(T::Boolean) }
  def authorized_to_update_protected_head_branch?
    policy_evaluator = pull_request.head_branch_rule_evaluator
    return true unless policy_evaluator

    policy_evaluator.authorized?(user)
  end

  # Returns true if the head ref of the pull request is protected in such a way that would prevent the current
  # user from directly pushing a merge commit. This accounts for locked branches, required status checks, required reviewers, or
  # required linear history, and any available admin overrides.
  sig { returns(T::Boolean) }
  def protection_prohibits_merge_on_head?
    policy_evaluator = pull_request.head_branch_rule_evaluator
    return false unless policy_evaluator

    !policy_evaluator.commit_authorized?(user) ||
      # Note that "PR only" bypass mode only allows bypass using a PR where the protected branch is the BASE branch
      (!policy_evaluator.can_override_required_linear_history?(actor: user, is_pull_request: false) &&
      policy_evaluator.required_linear_history_enabled?)
  end

  sig { returns(T::Boolean) }
  def conflict_editor_disabled?
    pull_request.cross_repo? && !GitHub.cross_repo_conflict_editor_enabled?
  end

  sig { returns(T.nilable(::PullRequestConflict)) }
  def conflicts
    return @conflicts if defined?(@conflicts)
    @conflicts = async_load_conflicts.sync
  end

  sig { returns(Promise[T.nilable(::PullRequestConflict)]) }
  def async_load_conflicts
    Platform::Loaders::ActiveRecord.load(::PullRequestConflict, pull_request.id, column: :pull_request_id, case_sensitive: false)
  end
end
