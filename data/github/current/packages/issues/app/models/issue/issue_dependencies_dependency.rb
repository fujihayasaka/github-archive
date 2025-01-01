# typed: strict
# frozen_string_literal: true

module Issue::IssueDependenciesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))

    has_many :blocked_by_relations, class_name: "IssueDependency", inverse_of: :source_issue
    has_many :blocked_by, through: :blocked_by_relations, source: :target_issue, class_name: "Issue"
    destroy_dependents_in_background :blocked_by_relations, sharding_key: :source_repository_id, sharding_value_key: :repository_id

    has_many :blocking_relations, class_name: "IssueDependency", inverse_of: :target_issue
    has_many :blocking, through: :blocking_relations, source: :source_issue, class_name: "Issue"
    destroy_dependents_in_background :blocking_relations

    has_one :issue_dependency_list, inverse_of: :issue
  end

  sig { params(target_issue: Issue, actor: User).returns(IssueDependency) }
  def add_blocked_by!(target_issue, actor)
    add_issue_dependency(target_issue, actor, IssueDependency::DependencyType::BlockedBy)
  end

  sig { params(target_issue: Issue).void }
  def remove_blocked_by!(target_issue)
    remove_issue_dependency(target_issue, IssueDependency::DependencyType::BlockedBy)
  end

  sig { params(target_issue: Issue, actor: User, dependency_type: IssueDependency::DependencyType).returns(IssueDependency) }
  def add_issue_dependency(target_issue, actor, dependency_type)
    # Convert dependency type enum to a symbol, which should match one of the keys in `IssueDependency.dependency_type`,
    # which is used to convert the symbol to an integer that is stored in the database.
    dependency_type = T.let(dependency_type.serialize, Symbol)
    IssueDependency.create!(
      source_issue: self,
      target_issue: target_issue,
      actor_id: actor.id,
      dependency_type: dependency_type
   )
  end

  sig { params(target_issue: Issue, dependency_type: IssueDependency::DependencyType).void }
  def remove_issue_dependency(target_issue, dependency_type)
    # Convert dependency type enum to a symbol, which should match one of the keys in `IssueDependency.dependency_type`,
    # which is used to convert the symbol to an integer that is stored in the database.
    dependency_type = T.let(dependency_type.serialize, Symbol)
    IssueDependency.find_by(
      source_issue: self,
      target_issue: target_issue,
      dependency_type: dependency_type
    )&.destroy!
  end

  sig { params(viewer: T.nilable(User), cap_filter: ConditionalAccess::Filter).returns(Promise[T::Array[Issue]]) }
  def async_filtered_blocked_by(viewer:, cap_filter:)
    async_filtered_dependencies(viewer: viewer, cap_filter: cap_filter, dependency_type: IssueDependency::DependencyType::BlockedBy)
  end

  sig { params(viewer: T.nilable(User), cap_filter: ConditionalAccess::Filter).returns(Promise[T::Array[Issue]]) }
  def async_filtered_blocking(viewer:, cap_filter:)
    async_filtered_dependencies(viewer: viewer, cap_filter: cap_filter, dependency_type: IssueDependency::DependencyType::Blocking)
  end

  # A private method to handle the filtering of dependencies based on the viewer's permissions
  sig { params(viewer: T.nilable(User), cap_filter: ConditionalAccess::Filter, dependency_type: IssueDependency::DependencyType).returns(Promise[T::Array[Issue]]) }
  private def async_filtered_dependencies(viewer:, cap_filter:, dependency_type:)
    dependencies = case dependency_type
    when IssueDependency::DependencyType::BlockedBy
      async_blocked_by
    when IssueDependency::DependencyType::Blocking
      async_blocking
    else
      T.absurd(dependency_type)
    end

    dependencies.then do |issues|
      authorized_issues = cap_filter.authorized_resources(issues)
      Promise.all(
        authorized_issues.map do |issue|
          Promise.all([issue.async_hide_from_user?(viewer), issue.async_readable_by?(viewer)]).then do |hidden, readable|
            issue if !hidden && readable
          end
        end
      ).then(&:compact)
    end
  end

  sig { returns(T.nilable(IssueDependencyList)) }
  def recalculate_issue_dependency_list!
    return issue_dependency_list&.recalculate! if issue_dependency_list

    IssueDependencyList.build(issue: self).recalculate!
  end

  # Loads the completion rate from the denormalized issue_dependency_list if available, and calculate otherwise.
  #
  # If calculate is true, then we calculate the issue dependency summary based on the current issue dependency state as opposed to
  # relying on the denormalized issue dependency list.
  sig { params(calculate: T::Boolean).returns(Promise[IssueDependencyList::Summary]) }
  def async_issue_dependencies_summary(calculate: false)
    return Promise.resolve(calculate_issue_dependency_summary) if calculate

    T.let(self.async_issue_dependency_list, Promise[T.nilable(IssueDependencyList)]).then do |issue_dependency_list|
      # return an empty summary unless there is a list to calculate from
      if issue_dependency_list
        issue_dependency_list.to_summary
      else
        IssueDependencyList::Summary.empty
      end
    end
  end

  # Calculates a summary of the dependency counts for an issue, querying the database for the current values.
  sig { returns(IssueDependencyList::Summary) }
  def calculate_issue_dependency_summary
    blocked_by_counts = blocked_by.group(:state).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    blocked_by = blocked_by_counts["open"] || 0
    total_blocked_by = blocked_by_counts.values.sum

    blocking_counts = blocking.group(:state).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    blocking = blocking_counts["open"] || 0
    total_blocking = blocking_counts.values.sum

    IssueDependencyList::Summary.new(
      blocked_by: blocked_by,
      total_blocked_by: total_blocked_by,
      blocking: blocking,
      total_blocking: total_blocking
    )
  end

  sig { returns(T::Boolean) }
  def has_dependencies?
    self.blocked_by.any? || self.blocking.any? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
