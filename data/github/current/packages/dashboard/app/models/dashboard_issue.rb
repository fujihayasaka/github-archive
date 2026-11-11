# typed: true
# frozen_string_literal: true

# An issue displayed on the dashboard above the home feed.
class DashboardIssue
  def initialize(issue, viewer:)
    @issue = issue
    @viewer = viewer
  end

  def to_h
    {
      author: issue.safe_user.display_login,
      title: issue.title,
      id: issue.id,
      number: issue.number,
      createdAt: issue.created_at,
      updatedAt: issue.updated_at,
      permalink: issue.permalink,
      commentCount: issue.issue_comments_count,
      # TODO: Remove repoNameWithOwner once clients have been updated to use repository
      repoNameWithOwner: {
        name: issue.repository.name,
        ownerLogin: issue.repository.owner.display_login
      },
      readByCurrentUser: issue.read_by_current_user,
      repository: {
        id: issue.repository.id,
        isPrivate: issue.repository.private?,
        name: issue.repository.name,
        ownerLogin: issue.repository.owner.display_login,
        copilotAgentEnabled: issue.repository.copilot_swe_agent_enabled?(viewer)
      },
      assignedToCopilot: assigned_to_copilot?,
    }
  end

  def ==(other)
    self.issue == other.issue
  end

  private

  attr_reader :issue, :viewer

  def repository_nwo_payload
    Repos::ReactPayload.current_repository_nwo_payload(issue.repository)
  end

  sig { returns T::Boolean }
  def assigned_to_copilot?
    copilot = copilot_integration&.bot

    copilot.present? && issue.assignees.include?(copilot)
  end

  sig { returns T.nilable(Integration) }
  def copilot_integration
    @copilot_integration ||= Apps::Privileged.integration(:copilot_swe_agent)
  end
end
