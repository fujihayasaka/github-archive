# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SyncMemexProjectItemByIdToIssuesGraphJob < ApplicationJob

  queue_as :sync_issue_to_issues_graph

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_NETWORK_ERRORS = [
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
  ].freeze

  retry_on(
    *RETRYABLE_NETWORK_ERRORS,
    wait: :polynomially_longer,
    attempts: 5,
  )

  sig { params(memex_project_item_id: Integer).void }
  def perform(memex_project_item_id)
    Failbot.push("gh.memex.item.id": memex_project_item_id)

    memex_project_item = MemexProjectItem
                            .includes(:memex_project)
                            .includes(:content)
                            .find_by(id: memex_project_item_id)

    unless memex_project_item
      GitHub.logger.info(
        "MemexProjectItem #{memex_project_item_id} not found",
        "code.namespace": "SyncMemexProjectItemByIdToIssuesGraphJob",
        "code.function": "perform",
        "gh.memex.item.id": memex_project_item_id,
      )
      return
    end

    unless memex_project_item.memex_project.present?
      GitHub.logger.info(
        "MemexProject #{memex_project_item.memex_project_id} not found",
        "code.namespace": "SyncMemexProjectItemByIdToIssuesGraphJob",
        "code.function": "perform",
        "gh.memex.item.id": memex_project_item_id,
        "gh.memex.project.id": memex_project_item.memex_project_id
      )
      return
    end

    unless memex_project_item.content.present?
      GitHub.logger.info(
        "Issue #{memex_project_item.content_id} not found",
        "code.namespace": "SyncMemexProjectItemByIdToIssuesGraphJob",
        "code.function": "perform",
        "gh.memex.item.id": memex_project_item_id,
        "gh.memex.project.id": memex_project_item.memex_project_id,
        "gh.issue.id": memex_project_item.content_id
      )
      return
    end

    memex_project_item.sync_to_hierarchy
  end
end
