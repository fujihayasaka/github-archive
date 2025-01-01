# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicatePullRequestAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::PullRequest,
    PlatformTypes::IssueOrPullRequest
  ].freeze

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

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
