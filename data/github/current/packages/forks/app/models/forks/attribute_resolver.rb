# typed: true
# frozen_string_literal: true

class Forks::AttributeResolver
  # Resolves attributes for a collection of forks

  sig { params(scope: ActiveRecord::Relation).void }
  def initialize(scope)
    @scope = scope
    @preloaded_scope = @scope.order("owner_login ASC, name ASC").select(
      :id, :pushed_at, Repository.stargazer_count_column
    ).to_a
  end

  def resolve
    @attributes ||= {
      stargazer_counts:,
      child_fork_counts:,
      open_issue_counts:,
      open_pull_request_counts:,
      last_updated:,
    }.freeze
  end

  sig { returns T::Array[Integer] }
  def ids_by_owner_login
    @ids_by_owner_login ||= @preloaded_scope.map(&:id)
  end

  private

  sig { returns(T::Hash[Integer, Integer]) }
  def stargazer_counts
    @stargazer_counts ||= sorted_count(@preloaded_scope.to_h { |fork| [fork.id, fork.stargazer_count] })
  end

  sig { returns(T::Hash[Integer, Integer]) }
  def child_fork_counts
    @child_fork_counts ||= sorted_count(
      Repository.where(parent_id: ids_by_owner_login, active: true).group(:id).count.to_h
    )
  end

  sig { returns(T::Hash[Integer, Integer]) }
  def open_issue_counts
    @open_issue_counts ||= sorted_count(open_issues_scope.without_pull_requests.count.to_h) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T::Hash[Integer, Integer]) }
  def open_pull_request_counts
    @open_pull_request_counts ||= sorted_count(open_issues_scope.with_pull_requests.count.to_h) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def open_issues_scope
    @open_issues_scope = Issue.where(repository_id: ids_by_owner_login).open_issues.grouped_by_repo
  end

  sig { returns(T::Hash[Integer, Time]) }
  def last_updated
    @last_updated ||= @preloaded_scope
      .pluck(:id, :pushed_at)
      .sort_by(&:last)
      .reverse  # Can't use sorted_count on a Time object.
      .to_h
  end

  sig { params(count: T::Hash[Integer, Integer]).returns(T::Hash[Integer, Integer]) }
  def sorted_count(count)
    Hash.new(0).merge(
      count.sort_by { |_, value| -value }.to_h
    )
  end
end
