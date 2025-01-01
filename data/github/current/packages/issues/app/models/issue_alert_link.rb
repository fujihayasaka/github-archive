# typed: true
# frozen_string_literal: true

# Model representing a tracking or "parent" relationship between an Issue and an Alert.
class IssueAlertLink < ApplicationRecord::Domain::IssuesPullRequests

  belongs_to :issue, class_name: "Issue", required: true
  belongs_to :actor, class_name: "User", required: true
  belongs_to :alert_repository, class_name: "Repository"

  validates :alert_repository, presence: true
  validates :alert_number, uniqueness: { scope: [:issue_id, :alert_type, :alert_repository] }

  after_commit :notify_socket_subscribers # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :alert_type, { code_scanning: 0 }

  # Public: Returns true if the given User has read access to the link
  def readable_by?(actor)
    issue&.readable_by?(actor) && alert_repository&.readable_by?(actor)
    # checking permission to read the alert repo following the pattern set in issue_link
  end

  # Public: Returns true if the given User has edit access to the link
  # Edit access to the tracking issue is enough. We want to allow removing links
  # even if the user doesn't have read access to the alert anymore
  def editable_by?(actor)
    issue&.editable_by?(actor)
  end

  def notify_socket_subscribers
    issue&.notify_socket_subscribers
  end

  def self.displayable_tracking_issues(repository:, alert_number:, viewer:)
    all_parent_issues = self.where(alert_number: alert_number, alert_repository: repository).includes(:issue).map(&:issue)
    readable_issues_promises = all_parent_issues.map do |issue|
      issue&.async_readable_by?(viewer).then do |readable|
        next issue if readable
      end
    end
    issues = Promise.all(readable_issues_promises).then { |readable_issues| readable_issues.compact }.sync
    issues.sort_by { |i| i.state == "open" ? 0 : 1 }
  end
end
