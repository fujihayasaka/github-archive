# typed: true
# frozen_string_literal: true

module Issue::IssueDependenciesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))

    has_many :blocked_by_relations, -> { scoped.blocked_by }, class_name: "IssueDependency", inverse_of: :source_issue
    has_many :blocked_by, through: :blocked_by_relations, source: :target_issue, class_name: "Issue"
    destroy_dependents_in_background :blocked_by_relations, sharding_key: :source_repository_id, sharding_value_key: :repository_id

    has_many :blocking_relations, -> { scoped.blocking }, class_name: "IssueDependency", inverse_of: :source_issue
    has_many :blocking, through: :blocking_relations, source: :target_issue, class_name: "Issue"
    destroy_dependents_in_background :blocking_relations, sharding_key: :source_repository_id, sharding_value_key: :repository_id
  end

  sig { params(target_issue: Issue, actor: User).returns(IssueDependency) }
  def add_blocked_by!(target_issue, actor)
    add_issue_dependency(target_issue, actor, :blocked_by)
  end

  sig { params(target_issue: Issue, actor: User).returns(IssueDependency) }
  def add_blocking!(target_issue, actor)
    add_issue_dependency(target_issue, actor, :blocking)
  end

  sig { params(target_issue: Issue, actor: User, dependency_type: Symbol).returns(IssueDependency) }
  def add_issue_dependency(target_issue, actor, dependency_type)
    IssueDependency.create!(
      source_issue: self,
      target_issue: target_issue,
      actor_id: actor,
      dependency_type:
   )
  end
end
