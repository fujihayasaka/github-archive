# typed: true
# frozen_string_literal: true

module PullRequest::CodeNavDependency
  extend T::Helpers

  requires_ancestor { PullRequest }
  # Returns a list of strings describing the languages detected
  # in the pull request's changed files.
  def all_languages_in_diff
    diffs.flat_map do |diff|
      Linguist::Language.find_by_extension(diff.path).map(&:name)
    end.uniq
  end
end
