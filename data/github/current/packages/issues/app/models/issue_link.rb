# typed: true
# frozen_string_literal: true

# Model representing directional relationship between Issues.
class IssueLink < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :source_issue, class_name: "Issue", required: true
  belongs_to :target_issue, class_name: "Issue", required: true
  belongs_to :actor, class_name: "User", required: true
  belongs_to :source_repository, class_name: "Repository"
  belongs_to :target_repository, class_name: "Repository"

  before_validation :set_source_repository
  before_validation :set_target_repository

  validates :source_repository, :target_repository, presence: true
  validates :target_issue_id, uniqueness: { scope: [:source_issue_id, :link_type] }
  validate  :check_tracking_source_and_target_inequality
  validate  :target_issue_type, on: :create

  after_commit :notify_socket_subscribers # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :link_type, { track: 0 }

  # Public: Returns true if the given User has read access to the link
  def readable_by?(actor)
    source_issue&.readable_by?(actor) && target_issue&.readable_by?(actor)
  end

  # Public: Returns true if the given User has edit access to the link
  # Edit access to the source issue is enough. We want to allow removing links
  # even if the user doesn't have read access to the target issue anymore
  def editable_by?(actor)
    source_issue&.editable_by?(actor)
  end

  def notify_socket_subscribers
    source_issue&.notify_socket_subscribers
  end

  private

  def set_source_repository
    self.source_repository = source_issue&.repository
  end

  def set_target_repository
    self.target_repository = target_issue&.repository
  end

  def check_tracking_source_and_target_inequality
    if source_issue_id == target_issue_id && track?
      errors.add(:base, :self_reference, message: "Tracking Source and Target have to be different")
    end
  end

  def target_issue_type
    if target_issue&.pull_request_id?
      errors.add(:target_issue, :strictly_issue, message: "Cannot link a pull request as a tracked issue")
    end
  end

end
