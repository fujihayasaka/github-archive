# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::PullRequestRevisionMarkerAdapter < Issue::Adapter::Base
  PULL_REQUEST_REVISION_MARKER = "PullRequestRevisionMarker"

  attr_reader :last_seen_commit_oid, :pull_request

  def initialize(context, last_seen_commit_oid:)
    @last_seen_commit_oid = last_seen_commit_oid
    @pull_request = context.pull_request
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
