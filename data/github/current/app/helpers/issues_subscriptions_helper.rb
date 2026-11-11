# typed: true
# frozen_string_literal: true

module IssuesSubscriptionsHelper
  include RelayHelper
  include IssuesReactGraphqlQueries

  QUERIES_REQUIRING_SUBSCRIPTION = [
    ISSUE_INDEX_PAGE_QUERY,
    SEARCH_PAGINATED_QUERY,
    ISSUE_DASHBOARD_PAGE_QUERY,
    ISSUE_DASHBOARD_CUSTOM_VIEW_PAGE_QUERY,
    ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY,
    ISSUE_VIEWER_VIEW_QUERY,
    MILESTONE_SHOW_QUERY,
  ]

  class GetPrecomputeSubscriptionError < StandardError; end

  def self.get_hash_for_path(path, query_id, result, preload_pull_requests: false)
    # check if we have a repo scoped search or a global search
    edges = (result.dig("data", "repository", "search", "edges") || result.dig("data", "search", "edges") || [])

    if edges.any?(&:nil?)
      # I'm leaving this failbot here in case there is a need to debug this further in the future.
      # But from what I've seen so far, those nil values are expected, as they result in either:
      # 1. Saml error
      # 2. IP not allowed
      Failbot.report(
        GetPrecomputeSubscriptionError.new,
        path: path,
        query_id: query_id,
        catalog_service: "github/issues",
      )
    end

    # get all the issue and pull request ids from the search result
    ids = edges
      .compact
      .map { |edge| edge.dig("node", "id") }
      .flatten
      .compact
      .filter { |id| id.start_with?("I_", "PR_") }

    issue_ids, pull_request_ids = ids.partition { |id| id.start_with?("I_") }

    subscriptions = {}
    issue_ids.each do |issue_id|
      subscription = IssuesReactGraphqlQueries::issue_row_subscription(issue_id)
      subscriptions[subscription.graphql_query_id] ||= {}
      subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_subscription_entry(issue_id)
    end

    return subscriptions unless preload_pull_requests

    pull_request_ids.each do |issue_id|
      subscription = IssuesReactGraphqlQueries::pull_request_row_subscription(issue_id)
      subscriptions[subscription.graphql_query_id] ||= {}
      subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_pull_request_subscription_entry(issue_id)
    end
    subscriptions
  end

  def self.compute_subscriptions_for_issues_dashboard_query(query_id, result, path = "", preload_pull_requests: false)
    return nil unless query_id == ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY.graphql_query_id
    get_hash_for_path(path, query_id, result, preload_pull_requests:)
  end

  def self.compute_subscriptions_for_issues_index_query(query_id, result, path = "", preload_pull_requests: false)
    return nil unless QUERIES_REQUIRING_SUBSCRIPTION.map(&:graphql_query_id).include?(query_id)
    get_hash_for_path(path, query_id, result, preload_pull_requests:)
  end

  def self.compute_subscriptions_for_milestone_show_query(query_id, result, path = "", preload_pull_requests: false)
    return nil unless QUERIES_REQUIRING_SUBSCRIPTION.map(&:graphql_query_id).include?(query_id)
    get_hash_for_path(path, query_id, result, preload_pull_requests:)
  end

  def self.compute_subscriptions_for_issue_viewer_query(query_id, result)
    return {} unless query_id == ISSUE_VIEWER_VIEW_QUERY.graphql_query_id
    issue_id = result.dig("data", "repository", "issue", "id")
    subscriptions = {}
    if issue_id
      subscription_array = IssuesReactGraphqlQueries::issue_viewer_subscriptions(issue_id)
      subscription_array.each do |subscription|
        subscriptions[subscription.graphql_query_id] ||= {}
        if subscription.name == "IssueViewerSubscriptionTimelineSubscription"
          subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_timeline_subscription_entry(issue_id)
        elsif subscription.name == "IssueViewerSubscriptionMetadataSubscription"
          subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_metadata_subscription_entry(issue_id)
        else
          subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_subscription_entry(issue_id)
        end
      end
    end

    sub_issue_subscriptions = self.compute_subscriptions_for_sub_issues(query_id, result)

    subscriptions.merge(sub_issue_subscriptions)
  end

  def self.compute_subscriptions_for_sub_issues(query_id, result)
    return {} unless query_id == ISSUE_VIEWER_VIEW_QUERY.graphql_query_id
    sub_issues = result.dig("data", "repository", "issue", "subIssues", "nodes") || []

    sub_issue_ids = sub_issues
      .compact
      .map { |edge| edge.dig("id") }
      .flatten
      .compact
      .filter { |id| id.start_with?("I_") }

    subscriptions = {}
    sub_issue_ids.each do |issue_id|
      subscription = IssuesReactGraphqlQueries::sub_issue_subscription(issue_id)
      subscriptions[subscription.graphql_query_id] ||= {}
      subscriptions[subscription.graphql_query_id][subscription.variables_key] = IssuesSubscriptionsHelper.get_subscription_entry(issue_id)
    end
    subscriptions
  end

  def self.get_subscription_entry(issue_id)
    {
      response: {
        data: {
          issueUpdated: {
            deletedCommentId: nil,
            issueBodyUpdated: nil,
            issueMetadataUpdated: nil,
            issueStateUpdated: nil,
            issueTimelineUpdated: nil,
            issueTitleUpdated: nil,
            issueReactionUpdated: nil,
            issueTransferStateUpdated: nil,
            issueTypeUpdated: nil,
            commentReactionUpdated: nil,
            commentUpdated: nil,
            subIssuesUpdated: nil,
            subIssuesSummaryUpdated: nil,
            parentIssueUpdated: nil,
            issueDependenciesSummaryUpdated: nil,
          }
        }
      },
      subscriptionId: GitHub::WebSocket.signed_channel(
        Platform::Subscription.current_format.generate_channel_name(
          topic: ":issueUpdated:id:#{issue_id}",
          subscription_arguments: { id: issue_id }
        )
      ) # this is the most important part
    }
  end

  def self.get_pull_request_subscription_entry(pull_request_id)
    {
      response: {
        data: {
          pullRequestInfoForListViewUpdated: {
            commentsUpdated: nil,
            reviewDecisionUpdated: nil,
            statusUpdated: nil,
            titleUpdated: nil,
          }
        }
      },
      subscriptionId: GitHub::WebSocket.signed_channel(
        Platform::Subscription.current_format.generate_channel_name(
          topic: ":pullRequestInfoForListViewUpdated:id:#{pull_request_id}",
          subscription_arguments: { id: pull_request_id }
        )
      )
    }
  end

  def self.get_timeline_subscription_entry(issue_id)
    {
      response: {
        data: {
          issueUpdated: {
            issueTimelineUpdated: nil,
          }
        }
      },
      subscriptionId: GitHub::WebSocket.signed_channel(
        Platform::Subscription.current_format.generate_channel_name(
          topic: ":issueUpdated:id:#{issue_id}",
          subscription_arguments: { id: issue_id }
        )
      )
    }
  end

  def self.get_metadata_subscription_entry(issue_id)
    {
      response: {
        data: {
          issueUpdated: {
            deletedCommentId: nil,
            issueBodyUpdated: nil,
            issueMetadataUpdated: nil,
            issueStateUpdated: nil,
            issueReactionUpdated: nil,
            issueTransferStateUpdated: nil,
            issueTypeUpdated: nil,
            issueTitleUpdated: nil,
            commentReactionUpdated: nil,
            commentUpdated: nil,
            subIssuesUpdated: nil,
            subIssuesSummaryUpdated: nil,
            parentIssueUpdated: nil,
            issueDependenciesSummaryUpdated: nil,
          }
        }
      },
      subscriptionId: GitHub::WebSocket.signed_channel(
        Platform::Subscription.current_format.generate_channel_name(
          topic: ":issueUpdated:id:#{issue_id}",
          subscription_arguments: { id: issue_id }
        )
      )
    }
  end
end
