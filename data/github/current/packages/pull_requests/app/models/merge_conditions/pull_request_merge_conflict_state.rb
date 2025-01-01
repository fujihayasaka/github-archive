# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestMergeConflictState < MergeConditions::BaseMergeCondition
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

  def conflicts
    return @conflicts if defined?(@conflicts)
    @conflicts = async_load_conflicts.sync
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
      isConflictResolvableInWeb: conflicts&.resolvable?
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

  def async_load_conflicts
    Platform::Loaders::ActiveRecord.load(::PullRequestConflict, @pull_request.id, column: :pull_request_id, case_sensitive: false)
  end

  def async_condition
    async_load_conflicts.then do |conflicts|
      @pull_request.enqueue_mergeable_update
      next if !conflicts

      # we treat merge conflicts as blocking for any type of merge and rebase conflicts as only blocking
      # if rebase is the selected merge method
      has_merge_conflict = conflicts.conflict_type == "merge_conflict"
      has_rebase_conflict = @merge_method == :rebase && conflicts.conflict_type == "rebase_conflict"

      if has_merge_conflict
        evaluation_result.errors << MERGE_CONFLICT_MESSAGE
      elsif has_rebase_conflict
        evaluation_result.errors << REBASE_CONFLICT_MESSAGE
      end
    end
  end
end
