# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicateIssueAdapter < Issue::Adapter::Base
  TYPES = T.let([
    PlatformTypes::Issue,
    PlatformTypes::IssueOrPullRequest
  ].freeze, T::Array[T.any(T.class_of(PlatformTypes::Issue), T.class_of(PlatformTypes::IssueOrPullRequest))])

  # app/views/issues/events/_marked_as_duplicates.html.erb
  attr_reader :id,
    :number,
    :repository,
    :resource_path,
    :state,
    :title,
    :__typename

  def initialize(context, issue:)
    super(context)

    @id = issue.global_relay_id
    @number = issue.number
    @repository = Issue::Adapter::DuplicateRepositoryAdapter.new(context, repository: issue.repository)
    @resource_path = resource_path_for(issue.path_uri)
    @title = issue.title
    @__typename = "Issue"
  end

  sig { override.returns(T::Array[T.any(T.class_of(PlatformTypes::Issue), T.class_of(PlatformTypes::IssueOrPullRequest))]) }
  def self.defined_types
    TYPES
  end
end
