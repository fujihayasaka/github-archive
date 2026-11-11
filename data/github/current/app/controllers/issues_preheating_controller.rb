# typed: true
# frozen_string_literal: true

class IssuesPreheatingController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include ApplicationController::DefaultRateLimitDependency
  include IssuesCacheTtlHelper

  skip_before_action :authorization_required
  before_action :login_required_redirect_for_public_repo

  READ_RATE_LIMIT = 400
  READ_RATE_LIMIT_ANON = 60

  rate_limit_requests \
    only: [:show, :index],
    max: :read_rate_limit,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    key: :rate_limit_key,
    at_limit: :render_rate_limited_response

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:show, :index]

  def index
    source = params[:source]

    owner_login = current_repository.owner.display_login
    repo_name = current_repository.name

    query = IssuesReactGraphqlQueries::ISSUE_INDEX_PAGE_QUERY
    operation_id = query.graphql_query_id

    # Assuming here that issues_default_best_match_sort and issues_search_type_gql are fully enabled
    variables = {
      "first" => 25,
      "labelPageSize" => 20,
      "name" => repo_name,
      "owner" => owner_login,
      "query" => "is:issue state:open repo:#{owner_login}/#{repo_name} sort:relevance-desc",
      "skip" => 0,
      "type" => "ISSUE_HYBRID",
    }

    query_result = execute_query(
      operation_id: operation_id,
      variables: variables,
      preheat_source: source,
    )

    return head :not_found unless query_result.respond_to?(:success?) && query_result.success?

    state = {
      data: {
        data: query_result.data,
        extensions: {},
        dataUpdatedAt: Time.now.to_i,
        preheatSource: source,
        ttl: compute_issue_index_cache_ttl(current_repository),
      },
      preheatSource: source,
    }

    result = {
      cacheValue: {
        queryHash: operation_id,
        state: state,
        variables: variables,
      }
    }

    render json: result.to_h
  end

  def show
    number = params[:number].to_i
    source = params[:source]
    owner_login = current_repository.owner.display_login
    repo_name = current_repository.name

    query = IssuesReactGraphqlQueries::ISSUE_VIEWER_VIEW_QUERY
    operation_id = query.graphql_query_id

    variables = {
      "count" => 15,
      "hideTimeline" => false,
      "number" => number,
      "owner" => owner_login,
      "repo" => repo_name,
    }

    query_result = execute_query(
      operation_id: operation_id,
      variables: variables,
    )

    return head :not_found unless query_result.respond_to?(:success?) && query_result.success?

    state = {
      data: {
        data: query_result.data,
        extensions: {},
        dataUpdatedAt: Time.now.to_i,
        preheatSource: source,
        ttl: 1209600000, # 2 weeks in milliseconds
      },
      preheatSource: source
    }

    result = {
      cacheValue: {
        queryHash: operation_id,
        state: state,
        variables: variables,
      }
    }

    render json: result.to_h
  end

  private

  def rate_limit_key
    if current_user
      "issues_preheating_controller:#{T.must(current_user).id}"
    else
      rate_limit_key_by_ip
    end
  end

  def read_rate_limit
    return READ_RATE_LIMIT if logged_in?

    READ_RATE_LIMIT_ANON
  end

  def render_rate_limited_response
    head :too_many_requests
  end
end
