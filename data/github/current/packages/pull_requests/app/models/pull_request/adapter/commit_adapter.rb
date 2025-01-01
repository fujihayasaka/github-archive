# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::CommitAdapter < Issue::Adapter::Base
  PULL_REQUEST_COMMIT = "PullRequestCommit"

  attr_reader :pull_request, :commit, :id

  def initialize(context, commit_oid:)
    super(context)
    @pull_request = context.pull_request
    @commit = context.commits_by_oid[commit_oid]
    @id = @commit.global_relay_id
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
