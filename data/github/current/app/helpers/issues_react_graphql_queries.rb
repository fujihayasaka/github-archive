# typed: true
# frozen_string_literal: true

module IssuesReactGraphqlQueries
  extend T::Sig
  include RelayHelper

  ISSUE_INDEX_PAGE_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issues-react/pages/__generated__/IssueIndexPageQuery.graphql.ts"),
    variables: nil,
  )
  # This is the query that is used to fetch the data for the list view on soft navigation
  SEARCH_PAGINATED_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issues-react/components/list/__generated__/SearchPaginatedQuery.graphql.ts"),
    variables: nil,
  )
  ISSUE_DASHBOARD_PAGE_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issues-react/pages/__generated__/IssueDashboardPageQuery.graphql.ts"),
    variables: nil
  )
  ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issues-react/pages/__generated__/IssueDashboardCustomViewPageQuery.graphql.ts"),
    variables: nil
  )
  ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issues-react/pages/__generated__/IssueDashboardKnownViewPageQuery.graphql.ts"),
    variables: nil
  )
  ISSUE_VIEWER_VIEW_QUERY = GraphQLRequest.new(
    query: Rails.root.join("ui/packages/issue-viewer/components/__generated__/IssueViewerViewQuery.graphql.ts"),
    variables: nil
  )
  ISSUE_VIEWER_SECONDARY_VIEW_QUERY_PATH = Rails.root.join("ui/packages/issue-viewer/components/__generated__/IssueViewerSecondaryViewQuery.graphql.ts")

  sig { params(issue_id: String).returns(GraphQLRequest) }
  def self.issue_row_subscription(issue_id)
    GraphQLRequest.new(
      query: Rails.root.join("ui/packages/list-view-items-issues-prs/components/__generated__/IssueRowSubscription.graphql.ts"),
      variables: { issueId: issue_id }
    )
  end

  sig { params(issue_id: String).returns(GraphQLRequest) }
  def self.issue_viewer_subscription(issue_id)
    GraphQLRequest.new(
      query: Rails.root.join("ui/packages/issue-viewer/components/__generated__/IssueViewerSubscription.graphql.ts"),
      variables: { issueId: issue_id }
    )
  end

  sig { params(issue_id: String).returns(GraphQLRequest) }
  def self.sub_issue_subscription(issue_id)
    GraphQLRequest.new(
      query: Rails.root.join("ui/packages/sub-issues/subscriptions/__generated__/subIssueSubscription.graphql.ts"),
      variables: { issueId: issue_id }
    )
  end
end
