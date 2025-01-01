# typed: true
# frozen_string_literal: true

module Dashboard::IssuesQueryConcern
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  INDEX_TAG_FILTER_SYMBOLS = [:label, :milestone, :author, :assignee, :review, :project, :sort, :open, :closed]

  def pulls_only?
    return @_pulls_only if defined?(@_pulls_only)
    @_pulls_only = ActiveRecord::Type::Boolean.new.deserialize(params[:pulls_only])
  end

  def pulls_only=(value)
    @_pulls_only = value
  end

  def parsed_issues_query=(value)
    @parsed_issues_query = value
  end

  def parsed_issues_query
    @parsed_issues_query ||= Search::Queries::IssueQuery.normalize(
      Search::Queries::IssueQuery.parse(params_or_default_query_string, current_user)
    )
  end

  def user_dashboard_lists_enabled?
    FeatureFlag.vexi.enabled?(:dashboard_pull_request_list, current_user, default: false) ||
    FeatureFlag.vexi.enabled?(:productivity_dashboard, current_user, default: false) ||
    FeatureFlag.vexi.enabled?(:dashboard_lists, current_user, default: false)
  end

  def params_or_default_query_string
    params[:q] || "is:#{pulls_only? ? :pr : :issue} is:open "
  end

  def default_search_tags
    %W[controller:#{controller_name} action:#{action_name} spammy:#{current_user&.spammy?} has_issues:#{current_repository&.has_issues?} logged_in:#{logged_in?}]
  end

  def query_parsed_search_tags
    search_tags = default_search_tags

    # is default query: query run on the /pulls or /issues page without any additional interaction
    is_default_query = false

    # when includes :assignee for the current user of @me
    is_self_assigned = false

    # when includes :author for the current user of @me
    is_self_authored = false

    # when is a exclusive issue search
    issues_only = false

    unless parsed_issues_query.nil?
      is_issue_search = parsed_issues_query.include?([:is, "issue"])
      is_pr_search = parsed_issues_query.include?([:is, "pr"])
      is_default_query = ::Search::Queries::IssueQuery.is_default_issues_index_query?(parsed_issues_query)

      issues_only = is_issue_search && !is_pr_search

      if logged_in?
        is_self_assigned = parsed_issues_query.include?([:assignee, T.must(current_user).display_login]) || parsed_issues_query.include?([:assignee, "@me"])
        is_self_authored = parsed_issues_query.include?([:author, T.must(current_user).display_login]) || parsed_issues_query.include?([:author, "@me"])
      end
    end

    # parsed_issues_query is currently an array of pairs, or a flat search query text.
    # We want to extract the filter symbols used.
    parsed_query_keys = []
    parsed_issues_query.each do |item|
      if item.is_a?(Array) && item.length == 2
        parsed_query_keys.append(item.first)
      end
    end

    INDEX_TAG_FILTER_SYMBOLS.each do |filter|
      filter_s = filter.to_s

      has_filter = parsed_issues_query.include?([:no, filter_s]) ||
        parsed_query_keys.include?(filter) ||
        parsed_issues_query.include?([:is, filter_s])

      search_tags.append("has_#{filter_s}_filter:#{has_filter}")
    end

    tags = %W[force_pulls:#{pulls_only?} force_issues:#{issues_only} is_default_query:#{is_default_query} is_self_assigned:#{is_self_assigned} is_self_authored:#{is_self_authored}]
    search_tags.concat(tags)
    search_tags
  end
end
