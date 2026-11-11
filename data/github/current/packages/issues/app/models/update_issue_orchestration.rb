# typed: true
# frozen_string_literal: true

class UpdateIssueOrchestration < IssueOrchestration
  # updates need to be enqueued so disable validation.
  def validate_no_duplicates; end

  def only_save_on_orchestration_end? = true

  persist_feature_flags(
    :issues_orchestrate_community_profile,
  )


  step :set_assignees, max_attempts: 2 do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    return if data[:assignee_data].blank?

    if user_assignee_ids = data.dig(:assignee_data, :user_assignee_ids)
      previous_assignee_ids = issue.assignees.map(&:id)

      assignees = User.where(id: user_assignee_ids)
      issue.skip_update_issue_orchestration = true

      begin
        assignees = issue.assignees = assignees
        issue.save!
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        Assignment.transaction do
          issue.run_callbacks(:save) do
            # Destroy existing records
            Assignment.where(issue_id: T.must(issue.id)).map(&:destroy!)

            # rubocop:disable GitHub/UpsertAll
            Assignment.upsert_all(assignees.map { |user| { assignee_id: user.id, issue_id: issue.id, repository_id: issue.repository_id } })

            # Refresh the assignees to behave more like calling `#assignees=`
            issue.assignees.reload
          end
        end
      end

      self.update! data: data.merge(issue_changed: true) if data[:issue_changed].blank?
    end
  end

  step :remove_agent_eyes_reaction do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    previous_assignee_ids = data[:previous_assignee_ids]
    return unless previous_assignee_ids

    current_assignee_ids = issue.assignees.map(&:id)
    removed_assignee_ids = previous_assignee_ids - current_assignee_ids

    if removed_assignee_ids.any?
      Issues.domain.copilot.remove_eyes_emoji_reaction(issue: issue, removed_assignee_ids: removed_assignee_ids, actor: actor)
    end
  end

  private

  sig { returns(CopilotContext) }
  def copilot_context
    IssueOrchestration.send(:deserialize_copilot_context, data[:copilot_context])
  end

  step :set_issue_changed do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue
    return if issue_changed?

    if issue.changed? || issue.saved_changes?
      self.update! data: data.merge(issue_changed: true)
    end
  end

  job_start

  step :trigger_copilot_job do
    T.bind(self, UpdateIssueOrchestration)
    return unless copilot_context
    return unless actor
    return unless issue = self.issue

    actor_user = T.must(actor)
    base_context = T.must(copilot_context)
    base_context_hash = T.cast(base_context, T::Hash[Symbol, T.untyped])

    repository = T.must(issue.repository)

    agent_specific = build_agent_specific_copilot_contexts(
      issue: issue,
      actor: actor_user,
      base_context: base_context_hash
    )
    # If there are no agent-specific contexts, fall back to the base context
    contexts_to_trigger = agent_specific.empty? ? [base_context_hash] : agent_specific

    contexts_to_trigger.each do |context|
      CopilotSweAgentJobHelper.trigger_job_with_error_handling(
        issue: issue,
        actor: actor_user,
        copilot_context: context,
        orchestration_type: "UpdateIssueOrchestration"
      )
    end
  end

  step :synchronize_search_index do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    issue.synchronize_search_index
  end

  step :instrument_update_event do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    if data[:title_or_body_changes].present?
      issue.instrument_update_event(**data[:title_or_body_changes])
    end
  end

  step :instrument_hydro_update_event do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue
    return unless data.fetch(:instrument_hydro_update_event_enabled, false)

    if data[:title_or_body_changes].present?
      previous_title = data[:title_or_body_changes][:old_title]
      previous_body = nil
      if issue_edit_id = data[:title_or_body_changes][:issue_edit_id]
        previous_edit = IssueEdit.find(issue_edit_id)
        previous_body = previous_edit.compressed_diff || ""
      end
      issue.instrument_hydro_update_event(previous_title: previous_title, previous_body: previous_body)
    end
  end

  step :update_close_issue_references do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    issue.update_close_issue_references if should_update_close_issue_references
  end

  step :sync_memex_items_updated_at do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue
    return unless issue_changed?

    issue.touch_memex_project_items
  end

  step :sync_pull_request_updated_at do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    issue.sync_pull_request_updated_at
  end

  step :destroy_pinned_comment_if_pr do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue
    return unless issue.pull_request?
    return unless data[:is_converting_to_pr]

    issue.pinned_issue_comment&.destroy
  end

  step :attach_matching_assets do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    body_changed = data.dig(:title_or_body_changes, :issue_edit_id).present?
    issue.attach_matching_assets if body_changed
  end

  step :reconcile_checklist do
    T.bind(self, UpdateIssueOrchestration)
    return unless reconcile_checklist?
    return unless issue = self.issue

    issue.reconcile_checklist
  end

  # max_attempts: 2 gives one retry in case of a transient Redis blip
  # when enqueuing the background job.
  step :update_repo_community_profile, max_attempts: 2 do
    T.bind(self, UpdateIssueOrchestration)
    return unless feature_enabled?(:issues_orchestrate_community_profile)
    return unless needs_community_profile_update?
    return unless issue = self.issue

    issue.update_repo_community_profile!
  end

  sig { returns(T::Boolean) }
  def issue_changed?
    !!data[:issue_changed]
  end
end
