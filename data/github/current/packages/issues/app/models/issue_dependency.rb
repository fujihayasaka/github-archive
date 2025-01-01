# typed: true
# frozen_string_literal: true

# Model representing directional relationship between Issues.
class IssueDependency < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :source_issue, class_name: "Issue", required: true
  belongs_to :target_issue, class_name: "Issue", required: true
  belongs_to :actor, class_name: "User", required: true
  belongs_to :source_repository, class_name: "Repository"
  belongs_to :target_repository, class_name: "Repository"

  before_validation :set_source_repository_id, on: :create
  before_validation :set_target_repository_id, on: :create

  validates :source_issue_id, :target_issue_id, :source_repository, :target_repository, :dependency_type, presence: true
  validates :target_issue_id, uniqueness: { scope: [:source_issue_id, :dependency_type] }

  validate :source_and_target_different
  validate :type_does_not_conflict
  validate :no_pull_requests

  scope :blocked_by,  -> { where(dependency_type: :blocked_by) }
  scope :blocking,  -> { where(dependency_type: :blocking) }
  scope :by_created, -> { order(created_at: :desc) }

  enum :dependency_type, {
    blocked_by: 0,
    blocking: 1
  }

  sig { returns(T.nilable(Symbol)) }
  def inverse_dependency_type
    case dependency_type
    when "blocking"
      :blocked_by
    when "blocked_by"
      :blocking
    else
      nil
    end
  end

  private

  sig { void }
  private def source_and_target_different
    return unless source_issue_id == target_issue_id
    errors.add(:target_issue_id, "cannot be the same as the source issue")
  end

  sig { void }
  private def type_does_not_conflict
    possible_dependency = IssueDependency.find_by(source_issue_id:, target_issue_id:, dependency_type: inverse_dependency_type)
    if possible_dependency
      errors.add(:dependency_type, "cannot have both #{dependency_type} and #{inverse_dependency_type} for the target issue")
    end
  end

  sig { void }
  private def no_pull_requests
    if T.must(source_issue).has_pull_request
      errors.add(:source_issue_id, "may only be an issue")
    end

    if T.must(target_issue).has_pull_request
      errors.add(:target_issue_id, "may only be an issue")
    end
  end

  sig { void }
  private def set_source_repository_id
    self.source_repository_id = T.must(source_issue).repository_id
  end

  sig { void }
  private def set_target_repository_id
    self.target_repository_id = T.must(target_issue).repository_id
  end
end
