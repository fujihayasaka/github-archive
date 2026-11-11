# typed: true
# frozen_string_literal: true

class Forks::EmptyForksComponent < ApplicationComponent
  sig { returns(Repository) }
  attr_reader :current_repository

  DOC_REFERENCES = {
    fork_a_repo: "https://docs.github.com/articles/fork-a-repo",
    use_pull_requests: "https://docs.github.com/articles/using-pull-requests"
  }.freeze

  sig { params(current_repository: Repository, root_has_forks: T::Boolean, query_has_results: T::Boolean).void }
  def initialize(current_repository, root_has_forks, query_has_results)
    @current_repository = current_repository
    @root_has_forks = root_has_forks
    @query_has_results = query_has_results
  end

  private

  def root_has_no_forks?
    !@root_has_forks
  end

  def query_has_no_results?
    !@query_has_results
  end

  def render?
    root_has_no_forks? || query_has_no_results?
  end
end
