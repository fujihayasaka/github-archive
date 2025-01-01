# typed: strict
# frozen_string_literal: true

class Platform::Models::RepositoryPlanFeatures
  extend T::Sig

  sig { returns(Repository) }
  attr_reader :repo

  sig { params(repo: Repository).void }
  def initialize(repo)
    @repo = repo
  end

  sig { returns(Promise[T::Boolean]) }
  def draft_pull_requests
    plan_supports?(:draft_prs)
  end

  sig { returns(Promise[T::Boolean]) }
  def team_review_requests
    repo.async_owner.then do |owner|
      owner.is_a?(Organization) && plan_supports?(:team_review_requests)
    end
  end

  sig { returns(Promise[T::Boolean]) }
  def codeowners
    plan_supports?(:codeowners)
  end

  sig { returns(Promise[Integer]) }
  def maximum_manual_review_requests
    plan_limit(:manual_review_requests)
  end

  sig { returns(Promise[Integer]) }
  def maximum_assignees
    plan_limit(:issue_pr_assignees)
  end

  sig { params(feature: Symbol).returns(Promise[T::Boolean]) }
  def plan_supports?(feature)
    Promise.all([repo.async_internal_repository, repo.async_business]).then do
      repo.async_plan_supports?(feature)
    end
  end

  sig { params(feature: Symbol).returns(Promise[Integer]) }
  def plan_limit(feature)
    repo.async_internal_repository.then do
      repo.async_plan_limit(feature)
    end
  end
end
