# typed: true
# frozen_string_literal: true

class Issue::Adapter::PullRequestAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::IssueOrPullRequest,
    PlatformTypes::PullRequest
  ].freeze

  attr_reader :resource_path, :repository

  def initialize(context, pull_request:)
    super(context)

    @pull_request = pull_request
    @resource_path = resource_path_for(pull_request.path_uri)

    # It is possible that the pull request source repository is outside of the issues repository
    @repository = if context.repository_adapter.id == pull_request.repository_id
      context.repository_adapter
    else
      Issue::Adapter::RepositoryAdapter.new(context, repository: pull_request.repository)
    end
  end

  # TODO issue_timeline: preload path_uri and use in async_path_uri
  # app/helpers/hovercard_helper.rb:258
  def async_path_uri
    @pull_request.async_path_uri
  end

  # app/helpers/issues_helper.rb:564
  def number
    @pull_request.number
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
