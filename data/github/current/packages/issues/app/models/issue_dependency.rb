# typed: strict
# frozen_string_literal: true

# Model representing directional relationship between Issues.
class IssueDependency < ApplicationRecord::Domain::IssuesPullRequests
  # Enumeration of all dependency types supported for issues.
  class DependencyType < T::Enum
    enums do
      # A 'blocking' dependency, where one issue is blocking another issue.
      Blocking = new(:blocking)
      # A 'blocked by' dependency, where an issue is blocked by another issue.
      BlockedBy = new(:blocked_by)
    end
  end

  belongs_to :source_issue, class_name: "Issue", required: true
  belongs_to :target_issue, class_name: "Issue", required: true
  belongs_to :actor, class_name: "User", required: true
  belongs_to :source_repository, class_name: "Repository"
  belongs_to :target_repository, class_name: "Repository"

  default_scope { order(created_at: :asc) }

  before_validation :set_source_repository_id, on: :create
  before_validation :set_target_repository_id, on: :create

  validates :source_issue_id, :target_issue_id, :source_repository, :target_repository, :dependency_type, presence: true
  validates :target_issue_id, uniqueness: { scope: [:source_issue_id, :dependency_type] }

  validate :source_and_target_different
  validate :type_is_blocked_by
  validate :no_pull_requests
  validate :no_two_issue_cycle
  validate :blocked_by_limit

  after_create_commit :instrument_creation
  after_destroy_commit :instrument_destruction

  MAX_BLOCKED_BY_RELATIONS = 100

  enum :dependency_type, {
    blocked_by: 0,
    # we are currently only supporting one-way relationships for dependencies
    # blocking: 1
  }

  private

  sig { void }
  private def source_and_target_different
    return unless source_issue_id == target_issue_id
    errors.add(:target_issue_id, "cannot be the same as the source issue")
  end

  sig { void }
  private def type_is_blocked_by
    return if dependency_type == "blocked_by"
    errors.add(:dependency_type, "we only support blocked_by relations for now")
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
  private def no_two_issue_cycle
    if IssueDependency.exists?(source_issue_id: target_issue_id, target_issue_id: source_issue_id, dependency_type: :blocked_by)
      errors.add(:base, "this dependency would create a cycle where the target is already blocked by the source")
    end
  end

  sig { void }
  private def blocked_by_limit
    if IssueDependency.where(source_issue_id: source_issue_id, source_repository_id: source_repository_id, dependency_type: :blocked_by).count >= MAX_BLOCKED_BY_RELATIONS
      errors.add(:source_issue_id, "cannot have more than #{MAX_BLOCKED_BY_RELATIONS} blocked-by relations")
      # we don't need waste time querying for more relations
      return
    end

    if IssueDependency.where(target_issue_id: target_issue_id, target_repository_id: target_repository_id, dependency_type: :blocked_by).count >= MAX_BLOCKED_BY_RELATIONS
      errors.add(:target_issue_id, "cannot have more than #{MAX_BLOCKED_BY_RELATIONS} blocking relations")
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

  sig { void }
  private def instrument_creation
    GlobalInstrumenter.instrument("blocked_by.add", {
      # Using actor here because actor_id is not set in context for creation
      actor_id: (actor || User.ghost).id,
      source_issue_repository_id: source_repository_id,
      source_issue: source_issue,
      target_issue_repository_id: target_repository_id,
      target_issue: target_issue,
    })
  end

  sig { void }
  private def instrument_destruction
    GlobalInstrumenter.instrument("blocked_by.remove", {
      # Using actor_id from context here because actor is set to issue creator for destruction
      actor_id: GitHub.context[:actor_id],
      source_issue_repository_id: source_repository_id,
      source_issue: source_issue,
      target_issue_repository_id: target_repository_id,
      target_issue: target_issue,
    })
  end
end
