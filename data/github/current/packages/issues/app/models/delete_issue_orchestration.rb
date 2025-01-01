# typed: true
# frozen_string_literal: true

class DeleteIssueOrchestration < IssueOrchestration
  step :create_deleted_issue do
    T.bind(self, DeleteIssueOrchestration) # appease sorbet until we can help it understand steps
    issue = T.must(self.issue)

    return if DeletedIssue.exists?(repository: issue.repository, number: issue.number)
    DeletedIssue.create!(repository: issue.repository, deleted_by: actor, number: issue.number, old_issue_id: issue.id)
  end

  step :instrument_deletion do
    T.bind(self, DeleteIssueOrchestration)
    issue = T.must(self.issue)
    GlobalInstrumenter.instrument("issue.deleted", { repository: issue.repository, actor: actor, issue: issue })
  end

  step :destroy_issue, max_attempts: 2 do
    T.bind(self, DeleteIssueOrchestration)
    T.must(self.issue).destroy!
  end

  job_start

  step :synchronize_search_index do
    T.bind(self, DeleteIssueOrchestration)

    RemoveFromSearchIndexJob.perform_later("issue", T.must(issue_id), T.must(repository_id))
  end
end
