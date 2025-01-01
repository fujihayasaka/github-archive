# typed: true
# frozen_string_literal: true

# When viewing the timeline of a PullRequest, matching commit comment threads from
# the base repo as well as the head repo will be shown in the timeline as well.
#
# Because a regular CommitCommentThread does not know the context it is shown in,
# it can't correctly handle things like restricting commit comments to those that
# were posted by users with write access after the pull request was locked.
#
# We work around this by introducing a wrapping type that contains the link
# between a PullRequest and the CommitCommentThread.
class Platform::Models::PullRequestCommitCommentThread
  include GitHub::Relay::GlobalIdentification
  extend Forwardable

  GLOBAL_ID_PATTERN = /\A(?<pull_request_id>\d*):(?<repository_id>\d*):(?<commit_oid>\w{40}):(?<path>.*):(?<position>\d*)\z/

  def self.load_from_global_id(id)
    match = id.match(GLOBAL_ID_PATTERN)
    return Promise.resolve(nil) unless match

    pull_request_id = match[:pull_request_id].to_i
    repository_id = match[:repository_id].to_i
    commit_oid = match[:commit_oid]
    path = match[:path].blank? ? nil : match[:path]&.force_encoding("UTF-8")
    position = match[:position].blank? ? nil : match[:position].to_i

    # Load the pull request
    Platform::Loaders::ActiveRecord.load(::PullRequest, pull_request_id, security_violation_behaviour: :nil).then do |pull_request|
      # Ensure the pull exists and the given repository id is equal to the head or the base repo
      next unless pull_request
      next if pull_request.head_repository_id != repository_id &&
              pull_request.base_repository_id != repository_id

      async_ensure_pull_request_contains_commit_oid(pull_request, commit_oid).then do |commit_contained|
        next unless commit_contained

        new(pull_request, repository_id, commit_oid, path, position)
      end
    end
  end

  # Ensure the given commit oid is part of the pull request.
  def self.async_ensure_pull_request_contains_commit_oid(pull_request, commit_oid)
    pull_request.async_historical_comparison.then(&:async_commit_oids).catch do |error|
      case error
      when GitRPC::ObjectMissing, GitRPC::CommandFailed, Repository::CommandFailed, GitHub::DGit::UnroutedError
        []
      else
        raise error # rubocop:disable GitHub/UsePlatformErrors
      end
    end.then do |commit_oids|
      commit_oids.include?(commit_oid)
    end
  end

  def self.id_for(pull_request_id, repository_id, commit_oid, path, position)
    "#{pull_request_id}:#{repository_id}:#{commit_oid}:#{path}:#{position}"
  end

  def initialize(pull_request, repository_id, commit_oid, path, position)
    @pull_request = pull_request
    @repository_id = repository_id

    @commit_oid = commit_oid
    @path = path
    @position = position
  end

  attr_reader :path, :position

  # Ensure at least one commit comment exists at the given path and
  # position in the repo and is viewable by `viewer`.
  def async_hide_from_user?(viewer)
    return @async_hide_from_user[viewer] if defined?(@async_hide_from_user)

    @async_hide_from_user = Hash.new do |hash, key|
      hash[key] = Platform::Loaders::PullRequestCommitCommentThreadExistsCheck.load(
        key, pull_request.id, repository_id, commit_oid, path, position
      ).then do |exists|
        !exists
      end
    end
    @async_hide_from_user[viewer]
  end

  def id
    self.class.id_for(pull_request.id, repository_id, commit_oid, path, position)
  end

  # Used by GraphQL authorization checks
  def async_pull_request
    Promise.resolve(pull_request)
  end

  # Used by GraphQL authorization checks
  def async_repository
    return @async_repository if defined?(@async_repository)

    @async_repository = Platform::Loaders::ActiveRecord.load(::Repository, repository_id)
  end

  def async_comments(viewer)
    return @async_comments[viewer] if defined?(@async_comments)

    @async_comments = Hash.new do |hash, key|
      hash[key] = Platform::Loaders::PullRequestCommitCommentThread.load(key, pull_request.id, repository_id, commit_oid, path, position)
    end
    @async_comments[viewer]
  end

  def async_commit
    async_repository.then do |repository|
      Platform::Loaders::GitObject.load(repository, commit_oid, expected_type: :commit)
    end
  end

  def ==(other)
    super || (other.instance_of?(self.class) && other.state == state)
  end
  alias_method :eql?, :==

  def hash
    state.hash
  end

  # Transitional method to convert a `PullRequestCommitCommentThread` back to a
  # regular `CommitCommentThread`. This is necessary to ease the transition
  # to the new fast-timeline architecture and should probably not be used
  # for other purposes.
  def async_to_commit_comment_thread(viewer)
    async_pull_request.then(&:async_repository).then do |repository|
      async_comments(viewer).then do |comments|
        ::CommitCommentThread.new(
          repository: repository,
          commit_id: commit_oid,
          path: path,
          position: position,
          comments: comments
        )
      end
    end
  end

  protected

  attr_reader :pull_request, :repository_id, :commit_oid

  def state
    [pull_request, repository_id, commit_oid, path, position]
  end
end
