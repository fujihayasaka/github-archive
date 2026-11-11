# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicatePullRequestAdapter < Issue::Adapter::Base
  TYPES = T.let([
    PlatformTypes::PullRequest,
    PlatformTypes::IssueOrPullRequest
  ].freeze, T::Array[T.any(T.class_of(PlatformTypes::PullRequest), T.class_of(PlatformTypes::IssueOrPullRequest))])

  # app/views/issues/events/_marked_as_duplicates.html.erb
  attr_reader :id,
    :title,
    :number,
    :resource_path,
    :repository,
    :__typename

  def initialize(context, pull_request:)
    super(context)

    @pull_request = pull_request
    @id = pull_request.global_relay_id
    @title = pull_request.title
    @number = pull_request.issue.number
    @resource_path = resource_path_for(pull_request.path_uri)
    @repository = Issue::Adapter::DuplicateRepositoryAdapter.new(context, repository: pull_request.repository)
    @__typename = "PullRequest"
  end

  sig { override.returns(T::Array[T.any(T.class_of(PlatformTypes::PullRequest), T.class_of(PlatformTypes::IssueOrPullRequest))]) }
  def self.defined_types
    TYPES
  end
end
