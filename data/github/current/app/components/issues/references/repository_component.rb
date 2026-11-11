# typed: true
# frozen_string_literal: true

class Issues::References::RepositoryComponent < ApplicationComponent
  attr_reader :issue, :counts, :repositories

  # repositories: Branches::TargetRepositoryQuery#writable_repositories
  #   The list of repositories writable by the current user.
  # counts: Hash<Integer, Integer>
  #   The hash of repository.id to number of selected pull requests and branches for that repository.
  # issue: Issue
  #   The issue being referenced.
  def initialize(issue:, counts:, repositories: [])
    @issue = issue
    @counts = counts
    @repositories = repositories
  end

  def octicon_name(repository)
    if repository.internal?
      "organization"
    elsif repository.private?
      "repo-locked"
    else
      "repo"
    end
  end

  def counter(repository)
    counts.fetch(repository.id, 0)
  end

end
