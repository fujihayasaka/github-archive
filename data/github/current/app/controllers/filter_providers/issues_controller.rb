# typed: true
# frozen_string_literal: true

class FilterProviders::IssuesController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam

  preload_features []

  # Both the index and show actions rely on the `repository_ids_for_context` method
  # from the RepositoriesDependency module, which makes use of the CAP filter under the hood.
  # Therefore, we can skip the CAP filter checks on these actions and reduce some of the overhead on the request.
  skip_before_action :perform_conditional_access_checks, only: [:index, :show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    issues = find_issues.map { |issue| format_response(issue) }
    respond_payload({ issues: issues })
  end

  def show
    if issue_from_query
      respond_payload(format_response(issue_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  def supports_nwo_query_value?
    true
  end

  memoize def search_parents_only?
    params[:parent]&.to_s == "true"
  end

  memoize def issue_from_query
    if repository_from_nwo_query
      number = nwo_query_value_reference[:number]
      Issue.find_by(number: number, repository_id: repository_from_nwo_query.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  def find_issues
    return [] unless repository_ids_for_context.any?
    if nwo_query_value_reference
      return issue_from_query ? [issue_from_query] : []
    end

    search_class = ::Search::Queries::ConditionalIssueQuery

    query = search_class.new(
      allow_insecure_user_to_server_app_query: !FeatureFlag.vexi.enabled_or_raise?(:secure_user_to_server_search), # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      current_user: current_user,
      user_session: user_session,
      repo_id: repository_ids_for_context,
      remote_ip: request&.remote_ip,
      phrase: es_query,
      per_page: maximum_result_limit,
      source_fields: false,
      type: "issue",
      ngram_title: true,
      index: ::Elastomer::Indexes::Issues.by_type("issue"),
      normalizer: ->(results) { results.filter_map { |r| r["_model"] } },
      context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
    )

    results = query.execute.results
  end

  def es_query
    [base_es_query, parent_es_query].reject(&:empty?).join(" ")
  end

  def base_es_query
    if number_from_query
      "in:number #{number_from_query}"
    elsif escaped_query.presence
      "in:title #{escaped_query.presence}"
    else
      ""
    end
  end

  def parent_es_query
    search_parents_only? ? "has:sub-issue" : ""
  end

  # Support searching by #issue_number if the repository context is set
  def number_from_query
    return unless escaped_query.start_with?("#")
    maybe_number = escaped_query[1..]
    Integer(maybe_number) rescue nil
  end

  def escaped_query
    Search.escape_characters(query_value)
  end

  def format_response(issue)
    {
      title: issue.title,
      titleHtml: GitHub::Goomba::TitleMarkdownFilter.call(issue.title),
      number: issue.number,
      nwoReference: issue.name_with_display_owner_reference,
      state: issue.state,
      stateReason: issue.state_reason,
    }
  end
end
