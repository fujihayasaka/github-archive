# typed: strict
# frozen_string_literal: true

# Model representing directional relationship between Issues.
class IssueDependency < ApplicationRecord::Domain::IssuesPullRequests
  include Repositories::BelongsToRepository

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
  belongs_to_repository_via_domain relation_name: :source_repository, foreign_key: :source_repository_id, class_name: "Repository", legacy_return_type: true, feature_flag: "repos_domain_associations"
  belongs_to_repository_via_domain relation_name: :target_repository, foreign_key: :target_repository_id, class_name: "Repository", legacy_return_type: true, feature_flag: "repos_domain_associations"

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

  after_commit :synchronize_related_issues_search_index

  MAX_BLOCKED_BY_RELATIONS = 100

  enum :dependency_type, {
    blocked_by: 0,
    # we are currently only supporting one-way relationships for dependencies
    # blocking: 1
  }

  sig { void }
  def instrument_transfer
    instrument_creation
    synchronize_related_issues_search_index
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  sig { params(actor: T.untyped).returns(Promise[T.untyped]) }
  def async_readable_by?(actor)
    Promise.all([
      source_issue&.async_readable_by?(actor),
      target_issue&.async_readable_by?(actor)
    ]).then do |(source_readable, target_readable)|
      source_readable && target_readable
    end
  end

  private

  # Prepare audit log data for the source issue
  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def source_issue_audit_log_data
    {
      issue: source_issue,
      title: "#{target_issue&.title} (#{target_issue&.repository&.name_with_display_owner}##{target_issue&.number})",
      repo: source_issue&.repository,
      org: source_issue&.repository&.organization,
    }
  end

  # Prepare audit log data for the target issue
  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def target_issue_audit_log_data
    {
      issue: target_issue,
      title: "#{source_issue&.title} (#{source_issue&.repository&.name_with_display_owner}##{source_issue&.number})",
      repo: target_issue&.repository,
      org: target_issue&.repository&.organization,
    }
  end

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
      GitHub.dogstats.increment("issue_dependency.blocked_by.cycle")
      errors.add(:base, "this dependency would create a cycle where the target is already blocked by the source")
    end
  end

  sig { void }
  private def blocked_by_limit
    if IssueDependency.where(source_issue_id: source_issue_id, source_repository_id: source_repository_id, dependency_type: :blocked_by).count >= MAX_BLOCKED_BY_RELATIONS
      GitHub.dogstats.increment("issue_dependency.blocked_by.limit_exceeded")
      errors.add(:source_issue_id, "cannot have more than #{MAX_BLOCKED_BY_RELATIONS} blocked-by relations")
      # we don't need waste time querying for more relations
      return
    end

    if IssueDependency.where(target_issue_id: target_issue_id, target_repository_id: target_repository_id, dependency_type: :blocked_by).count >= MAX_BLOCKED_BY_RELATIONS
      GitHub.dogstats.increment("issue_dependency.blocking.limit_exceeded")
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
    # Instrument for webhooks and audit log
    if source_issue && target_issue
      GitHub.instrument("issue_dependencies.blocked_by_add", {
        blocked_issue_id: source_issue_id,
        blocking_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        **source_issue_audit_log_data,
      })
      GitHub.instrument("issue_dependencies.blocking_add", {
        blocked_issue_id: source_issue_id,
        blocking_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        **target_issue_audit_log_data,
      })
    end

    # Instrument hydro events
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
    current_user = User.find_by(id: GitHub.context[:actor_id]) || User.ghost
    # Instrument for webhooks and audit log
    if source_issue && target_issue
      GitHub.instrument("issue_dependencies.blocked_by_remove", {
        blocked_issue_id: source_issue_id,
        blocking_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        **source_issue_audit_log_data,
      })
      GitHub.instrument("issue_dependencies.blocking_remove", {
        blocked_issue_id: source_issue_id,
        blocking_issue_id: target_issue_id,
        actor_id: GitHub.context[:actor_id],
        **target_issue_audit_log_data,
      })
    end

    GlobalInstrumenter.instrument("blocked_by.remove", {
      # Using actor_id from context here because actor is set to issue creator for destruction
      actor_id: GitHub.context[:actor_id],
      source_issue_repository_id: source_repository_id,
      source_issue: source_issue,
      target_issue_repository_id: target_repository_id,
      target_issue: target_issue,
    })
  end

  sig { void }
  private def synchronize_related_issues_search_index
    source_issue&.synchronize_search_index
    target_issue&.synchronize_search_index
  end
end
