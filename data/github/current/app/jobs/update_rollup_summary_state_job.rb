# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateRollupSummaryStateJob < ApplicationJob
  queue_as :kubernetes_notifications

  RetryableError = Class.new(RuntimeError)

  retry_on_dirty_exit
  retry_on RetryableError, wait: :polynomially_longer

  attr_reader :repo_id, :issue_id, :issue_event_id, :options

  def perform(repo_id, issue_id, issue_event_id, options = {})
    begin
      status = :error
      status = update(repo_id, issue_id, issue_event_id)
    ensure
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.repo.id" => repo_id,
        "gh.issue.id" => issue_id,
        "gh.issue.event.id" => issue_event_id,
        "gh.notifyd.status" => status.to_s
      )
      GitHub.dogstats.increment("update_rollup_summary_state.perform.count", tags: ["status:#{status}"])
    end
  end

  def update(repo_id, issue_id, issue_event_id)
    repository = Repository.find_by(id: repo_id)
    return :no_repository unless repository

    issue = Issue.find_by(id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return :no_issue unless issue

    rollup_response = GitHub.newsies.web.find_rollup_summary_by_thread(repository, issue)
    raise RetryableError unless rollup_response.success?
    summary = rollup_response.value

    issue_event = IssueEvent.find(issue_event_id).event
    last_summarized_event = IssueEvent.summarized_events.where(issue_id: issue_id).last
    return :no_last_summarized unless last_summarized_event
    last_summarized_issue_event = last_summarized_event.event

    return :no_last_summarized unless issue_event == last_summarized_issue_event

    response = with_write do
      NotificationSummary.throttle do
        GitHub.newsies.web.update_rollup_summary(summary, issue_event)
      end
    end

    return :no_summary unless response

    raise RetryableError unless response.success?

    :success
  end
end
