# typed: true
# frozen_string_literal: true

# This component is basically a port of the Codespaces::RepositorySelectView.
# The main differences are as follows:
# - We defer our query logic to an instance of Branches::TargetRepositoryQuery.
# - In the markup we don't autosubmit the parent form when the user selects a repo.
class Issues::Branch::TargetRepositoryComponent < ApplicationComponent
  attr_reader :selected_repository, :issue, :query, :current_repository

  def initialize(selected_repository:, issue:, query:, current_repository:)
    @current_repository = current_repository
    @issue = issue
    @query = query
    @selected_repository = selected_repository
  end

  def selected?(repo)
    repo == selected_repository
  end
end
