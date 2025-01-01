# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceSourceIssueAdapter < Issue::Adapter::CrossReferenceSourceAdapter
  attr_reader :number,
    :repository,
    :resource_path,
    :state,
    :state_reason,
    :title

  # app/views/issues/events/_cross_reference.html.erb
  attr_reader :__typename

  TYPES = T.let([
    PlatformTypes::Issue,
    PlatformTypes::IssueOrPullRequest
  ].freeze, T::Array[T.any(T.class_of(PlatformTypes::Issue), T.class_of(PlatformTypes::IssueOrPullRequest))])

  def initialize(context, issue:)
    super(context, issue: issue)

    @issue = issue

    @number = issue.number
    @repository = Issue::Adapter::CrossReferenceSourceRepositoryAdapter.new(context, repository_id: issue.repository_id)

    # see app/platform/enums/issue_state.rb
    @state = issue.state.upcase
    @state_reason = issue.state_reason&.upcase
    @title = issue.title

    @__typename = "Issue"
  end

  # Used by Closables::StateComponent.
  def open?
    @state == "OPEN"
  end

  # Used by Closables::StateComponent.
  def closed?
    @state == "CLOSED"
  end

  sig { override.returns(T::Array[T.any(T.class_of(PlatformTypes::Issue), T.class_of(PlatformTypes::IssueOrPullRequest))]) }
  def self.defined_types
    TYPES
  end
end
