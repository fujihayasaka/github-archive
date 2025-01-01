# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicateIssueAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Issue,
    PlatformTypes::IssueOrPullRequest
  ].freeze

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

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
