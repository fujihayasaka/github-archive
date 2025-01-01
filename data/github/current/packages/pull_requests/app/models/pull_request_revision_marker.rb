# typed: true
# frozen_string_literal: true

class PullRequestRevisionMarker
  attr_accessor :pull_request, :last_seen_commit_oid, :created_at

  include GitHub::Relay::GlobalIdentification

  def initialize(pull_request, last_seen_commit_oid, created_at)
    @pull_request = pull_request
    @last_seen_commit_oid = last_seen_commit_oid
    @created_at = created_at
  end

  def timeline_sort_by
    raise "These markers aren't intended to be sorted into the timeline"
  end

  # Used by ability check, see Platform::Abilities#PullRequestRevisionMarker
  def async_pull_request
    Promise.resolve(pull_request)
  end

  def async_last_seen_commit
    Platform::Loaders::GitObject.load(pull_request.repository, last_seen_commit_oid)
  end

  # Public: Lookup latest PR revision marker for given PR and viewer
  #
  # pull_request - PullRequest
  # viewer       - User viewing the PullRequest
  #
  # Returns PullRequestRevisionMarker
  def self.latest_for(pull_request, viewer)
    return if viewer.nil?

    latest_revision = LastSeenPullRequestRevision.latest_for(pull_request.id, viewer.id).first
    return if latest_revision.nil?

    new(
      pull_request,
      latest_revision.last_revision,
      latest_revision.created_at,
    )
  end

  def ==(other)
    super || (other.instance_of?(self.class) && other.state == state)
  end
  alias_method :eql?, :==

  def hash
    state.hash
  end

  def global_id
    "#{pull_request.id}:#{last_seen_commit_oid}"
  end

  protected

  def state
    [pull_request, last_seen_commit_oid, created_at]
  end
end
