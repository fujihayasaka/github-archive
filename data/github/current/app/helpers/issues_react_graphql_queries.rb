# typed: true
# frozen_string_literal: true

module IssuesReactGraphqlQueries
  include RelayHelper

  ISSUE_INDEX_PAGE_QUERY = GraphQLRequest.new(
    name: "IssueIndexPageQuery",
    variables: nil,
  )
  # This is the query that is used to fetch the data for the list view on soft navigation
  SEARCH_PAGINATED_QUERY = GraphQLRequest.new(
    name: "SearchPaginatedQuery",
    variables: nil,
  )
  REPOSITORY_MILESTONE_PAGE_QUERY = GraphQLRequest.new(
    name: "RepositoryMilestonePageQuery",
    variables: nil,
  )
  ISSUE_DASHBOARD_PAGE_QUERY = GraphQLRequest.new(
    name: "IssueDashboardPageQuery",
    variables: nil
  )
  ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY = GraphQLRequest.new(
    name: "IssueDashboardCustomViewPageQuery",
    variables: nil
  )
  ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY = GraphQLRequest.new(
    name: "IssueDashboardKnownViewPageQuery",
    variables: nil
  )
  ISSUE_VIEWER_VIEW_QUERY = GraphQLRequest.new(
    name: "IssueViewerViewQuery",
    variables: nil
  )
  MILESTONE_SHOW_QUERY = GraphQLRequest.new(
    name: "RepositoryMilestonePageQuery",
    variables: nil
  )

  ISSUE_VIEWER_SECONDARY_VIEW_QUERY_NAME = "IssueViewerSecondaryViewQuery"
  ISSUE_INDEX_SECONDARY_QUERY_NAME = "IssueRowSecondaryQuery"


  sig { params(issue_id: String).returns(GraphQLRequest) }
  def self.issue_row_subscription(issue_id)
    GraphQLRequest.new(
      name: "IssueRowSubscription",
      variables: { issueId: issue_id }
    )
  end

  sig { params(pull_request_id: String).returns(GraphQLRequest) }
  def self.pull_request_row_subscription(pull_request_id)
    GraphQLRequest.new(
      name: "PullRequestRowSubscription",
      variables: { pullRequestId: pull_request_id }
    )
  end

  sig { params(issue_id: String).returns(T::Array[GraphQLRequest]) }
  def self.issue_viewer_subscriptions(issue_id)
    [
      GraphQLRequest.new(
        name: "IssueViewerSubscriptionMetadataSubscription",
        variables: { issueId: issue_id }
      ),
      GraphQLRequest.new(
        name: "IssueViewerSubscriptionTimelineSubscription",
        variables: { issueId: issue_id }
      )
    ]
  end

  sig { params(issue_id: String).returns(GraphQLRequest) }
  def self.sub_issue_subscription(issue_id)
    GraphQLRequest.new(
      name: "subIssueSubscription",
      variables: { issueId: issue_id }
    )
  end
end
