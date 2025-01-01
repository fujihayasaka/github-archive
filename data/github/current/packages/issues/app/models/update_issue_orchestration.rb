# typed: true
# frozen_string_literal: true

class UpdateIssueOrchestration < IssueOrchestration
  # updates need to be enqueued so disable validation.
  def validate_no_duplicates; end

  def only_save_on_orchestration_end? = true

  step :set_assignees, max_attempts: 2 do
    T.bind(self, UpdateIssueOrchestration)

    issue = self.issue
    return if issue.nil?

    return if data[:assignee_data].blank?

    if user_assignee_ids = data.dig(:assignee_data, :user_assignee_ids)
      assignees = User.where(id: user_assignee_ids)
      issue.skip_update_issue_orchestration = true

      begin
        assignees = issue.assignees = assignees
        issue.assignments.each { |a| a.skip_touch_issue_updated_at = true }
        issue.save!
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        raise e unless GitHub.flipper[:use_upsert_to_prevent_conflicts].enabled?

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

  step :set_issue_changed do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?
    return if data[:issue_changed].to_s == "true"

    issue_changed = T.must(issue).changed? || T.must(issue).saved_changes?

    return unless issue_changed

    self.update! data: data.merge(issue_changed: issue_changed)
  end

  job_start

  step :synchronize_search_index do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?

    T.must(issue).synchronize_search_index
  end

  step :instrument_update_event do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?

    if data[:title_or_body_changes].present?
      T.must(issue).instrument_update_event(**data[:title_or_body_changes])
    end
  end

  step :instrument_hydro_update_event do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?
    return unless data.fetch(:instrument_hydro_update_event_enabled, false)

    if data[:title_or_body_changes].present?
      previous_title = data[:title_or_body_changes][:old_title]
      previous_body = nil
      if issue_edit_id = data[:title_or_body_changes][:issue_edit_id]
        previous_edit = IssueEdit.find(issue_edit_id)
        previous_body = previous_edit.compressed_diff || ""
      end
      T.must(issue).instrument_hydro_update_event(previous_title: previous_title, previous_body: previous_body)
    end
  end

  step :update_close_issue_references do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?

    T.must(issue).update_close_issue_references if should_update_close_issue_references
  end

  step :sync_memex_items_updated_at do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?
    return if data[:issue_changed].blank?

    if data[:issue_changed]
      T.must(issue).touch_memex_project_items
    end
  end

  step :sync_pull_request_updated_at do
    T.bind(self, UpdateIssueOrchestration)
    return if issue.nil?

    T.must(issue).sync_pull_request_updated_at
  end

  step :attach_matching_assets do
    T.bind(self, UpdateIssueOrchestration)
    return unless issue = self.issue

    body_changed = data.dig(:title_or_body_changes, :issue_edit_id).present?
    issue.attach_matching_assets if body_changed
  end
end
