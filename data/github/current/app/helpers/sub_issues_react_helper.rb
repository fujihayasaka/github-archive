# typed: true
# frozen_string_literal: true

module SubIssuesReactHelper
  extend T::Helpers
  include GitHub::Memoizer
  include FeatureFlagHelper

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  ALLOWED_SUB_ISSUES_QUERIES = T.let(%w[
    IssueViewerViewQuery
    IssueViewerSecondaryViewQuery
    SubIssuesListItem_NestedSubIssuesQuery
  ], T::Array[String])

  def bucketize_sub_issues_count(count)
    case count
    when 0..5
      "xs"
    when 6..15
      "sm"
    when 15..30
      "m"
    when 31..50
      "l"
    when 51..75
      "xl"
    else
      "xxl"
    end
  end

  def get_sub_issues_tags(data)
    issue = data.dig("repository", "issue") || data.dig("node")

    return unless issue

    has_parent_key = issue.key?("parent")
    has_sub_issues_connection_key = issue.key?("subIssuesConnection")
    has_sub_issues_key = issue.key?("subIssues")

    return unless has_parent_key || has_sub_issues_connection_key || has_sub_issues_key

    metric_tags = []

    metric_tags << "has_parent:#{!issue.dig("parent").nil?}"

    total_sub_issue_nodes = issue.dig("subIssues", "nodes")&.length
    total_sub_issue_connection = issue.dig("subIssuesConnection", "totalCount")
    total_sub_issues = total_sub_issue_nodes || total_sub_issue_connection || 0
    has_sub_issues = total_sub_issues > 0
    metric_tags << "has_sub_issues:#{has_sub_issues}"

    if has_sub_issues
      metric_tags << "sub_issues_bucket:#{bucketize_sub_issues_count(total_sub_issues)}"
    end

    metric_tags
  end

  def get_sub_issues_add_query_time_tags_fn
    -> (operation_name, data) do
      next unless operation_name && data.is_a?(Hash)

      next unless ALLOWED_SUB_ISSUES_QUERIES.include?(operation_name)

      get_sub_issues_tags(data)
    end
  end
end
