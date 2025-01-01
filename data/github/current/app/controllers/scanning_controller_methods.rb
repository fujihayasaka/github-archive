# typed: true
# frozen_string_literal: true

module ScanningControllerMethods
  extend T::Sig
  extend T::Helpers
  include CommitHelper

  requires_ancestor { ApplicationController }

  # Load the commits for the given commit oids.
  #
  # Returns an array of raw Commit objects from `app/models/commit.rb`.
  sig { params(commit_oids: T::Array[String]).returns(T::Array[Commit]) }
  def load_commits(commit_oids)
    T.cast(
      Platform::Loaders::GitObject.load_all(current_repository, commit_oids.uniq, expected_type: "commit").sync.compact,
      T::Array[Commit])
  end

  sig { params(commit_oids: T::Array[String]).returns(T::Hash[String, Commit]) }
  def commits_by_oid(commit_oids)
    commits = load_commits(commit_oids)
    prefill_for_condensed_commit_view(commits, current_user)

    T.cast(commits.index_by(&:oid), T::Hash[String, Commit])
  end

  def check_code_scanning_read
    render_404 unless current_repository.code_scanning_readable_by?(current_user)
  end

  def check_code_scanning_write
    render_404 unless current_repository.code_scanning_writable_by?(current_user)
  end
end
