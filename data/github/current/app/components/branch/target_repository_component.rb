# typed: true
# frozen_string_literal: true

# This component is basically a port of the Codespaces::RepositorySelectView.
# The main differences are as follows:
# - We defer our query logic to an instance of BranchIssueReferences::TargetRepositoryQuery.
# - In the markup we don't autosubmit the parent form when the user selects a repo.
class Branch::TargetRepositoryComponent < ApplicationComponent
  attr_reader :selected_repository, :issue, :query, :current_repository

  def initialize(selected_repository:, query:, current_repository:, repository_list: nil)
    @current_repository = current_repository
    @query = query
    @selected_repository = selected_repository
    @repository_list = repository_list
  end

  def selected?(repo)
    repo == selected_repository
  end

  def repository_list
    @repository_list
  end
end
