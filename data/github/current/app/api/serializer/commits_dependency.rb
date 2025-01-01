# typed: true
# frozen_string_literal: true

module Api::Serializer::CommitsDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  def simple_commit_hash(commit)
    return nil unless commit
    {
      id:        commit.oid,
      tree_id:   commit.tree_oid,
      message:   commit.message,
      timestamp: time(commit.committed_date),
      author: {
        name: commit.author_name,
        email: commit.author_email,
      },
      committer: {
        name:  commit.committer_name,
        email: commit.committer_email,
      },
    }
  end
end
