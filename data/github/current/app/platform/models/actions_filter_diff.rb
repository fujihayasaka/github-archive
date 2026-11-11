# typed: true
# frozen_string_literal: true

class Platform::Models::ActionsFilterDiff
  attr_reader :repository, :advisory, :paths, :merge_base

  def initialize(repo, paths, advisory = nil, merge_base: nil)
    @repository = repo
    @paths = paths
    @advisory = advisory
    @merge_base = merge_base
  end

  def self.empty_diff(repo, merge_base: nil)
    new(repo, [], "empty", merge_base: merge_base)
  end

  def self.unavailable(repo, reason, merge_base: nil)
    new(repo, [], "unavailable:#{reason}", merge_base: merge_base)
  end

  def self.too_many_commits(repo, merge_base: nil)
    new(repo, [], "too_many_commits", merge_base: merge_base)
  end

  def self.truncated(repo, paths, merge_base: nil)
    new(repo, paths, "truncated", merge_base: merge_base)
  end
end
