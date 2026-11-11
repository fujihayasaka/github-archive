# typed: true
# frozen_string_literal: true

class Codespaces::GitCommitDivergenceComponent < ApplicationComponent
  attr_reader :codespace, :small_variant, :extra_classes

  def initialize(codespace:, small_variant: false, extra_classes: "")
    @codespace = codespace
    @small_variant = small_variant
    @extra_classes = extra_classes
  end

  def display_commit_status
    commits_ahead = codespace.commits_ahead
    return no_changes_el unless (codespace.has_uncommitted_changes?) || (commits_ahead && commits_ahead != 0)

    ahead = "is #{pluralize(commits_ahead, "commit")} ahead of remote" if commits_ahead != 0
    dirty = "has uncommitted changes" if codespace.has_uncommitted_changes?

    return "This codespace #{ahead} and #{dirty}" if ahead && codespace.has_uncommitted_changes?
    "This codespace #{ahead || dirty}"
  end

  def number_of_changes
    return codespace.commits_ahead if !codespace.has_uncommitted_changes?
    codespace.commits_ahead + 1
  end

  def add_style
    return "" if @small_variant
    "white-space:nowrap; overflow:hidden;"
  end

  def no_changes_el
    content_tag("i", "No changes")
  end
end
