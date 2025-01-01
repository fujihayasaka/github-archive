# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceSourcePullRequestAdapter < Issue::Adapter::CrossReferenceSourceAdapter
  TYPES = [
    # app/views/issues/events/_cross_reference.html.erb
    PlatformTypes::PullRequest,
    PlatformTypes::IssueOrPullRequest
  ].freeze

  # app/views/issues/events/_cross_reference.html.erb
  attr_reader :database_id,
    :is_draft,
    :number,
    :repository,
    :resource_path,
    :state,
    :__typename,
    :title

  def initialize(context, pull_request:)
    super(context, issue: pull_request.issue)

    @pull_request = pull_request
    issue = pull_request.issue

    @database_id = pull_request.id
    @is_draft = pull_request.draft?
    @number = issue.number
    # app/platform/interfaces/repository_node.rb
    @repository = Issue::Adapter::CrossReferenceSourceRepositoryAdapter.new(context, repository_id: pull_request.repository_id)

    # app/platform/objects/pull_request.rb
    @state = pull_request.issue_state.upcase
    @title = issue.title

    @__typename = "PullRequest"
  end

  # app/views/issues/events/_cross_reference.html.erb
  def is_draft?
    @is_draft
  end

  def is_in_merge_queue?
    return @is_in_merge_queue if defined? @is_in_merge_queue
    @is_in_merge_queue = @pull_request.in_merge_queue?
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
