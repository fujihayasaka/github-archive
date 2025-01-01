# typed: true
# frozen_string_literal: true

class Platform::Models::ActionsFilterDiff
  attr_reader :repository, :advisory, :paths

  def initialize(repo, paths, advisory = nil)
    @repository = repo
    @paths = paths
    @advisory = advisory
  end

  def self.empty_diff(repo)
    new(repo, [], "empty")
  end

  def self.unavailable(repo, reason)
    new(repo, [], "unavailable:#{reason}")
  end

  def self.too_many_commits(repo)
    new(repo, [], "too_many_commits")
  end
end
