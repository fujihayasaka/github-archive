# typed: true
# frozen_string_literal: true

class LabelsController < AbstractRepositoryController
  include LabelEducationHelper
  include Issues::RateLimitsDependency
  include IssuesReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :pushers_only, except: [:index, :show]
  before_action :writable_repository_required, except: [:index, :show]
  before_action :parse_json_params, only: [:create, :update]
  layout "repository", only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  javascript_bundle :"issues-react", only: [:index], unless: :use_issues_data_router?
  javascript_bundle :"issues", only: [:index], if: :use_issues_data_router?

  allow_verified_fetch only: [:index, :create, :update, :destroy]

  RATE_LIMITS_FEATURES = [
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  rate_limit_requests \
    only: [:index],
    max: ISSUES_BOT_RATE_LIMIT_MAX,
    ttl: 1.minute,
    key: :issues_bot_rate_limit_key,
    if: :issues_bot_rate_limiting_enabled?,
    at_limit: :issues_bot_rate_limit_at_limit

  def index
    if use_issues_data_router?
      issues_data_router_label_index_handler
    else
      issue_react_label_index_handler
    end
  end

  def show
    if label = current_repository.labels.find_by_name(params[:id])
      redirect_to url_for(controller: :issues, action: :index, labels: label.name)
    else
      render_404
    end
  end

  def create
    variables = {
      "input" => {
        "repositoryId" => params[:repositoryId],
        "color" => params[:color],
        "name" => params[:name],
        "description" => params[:description],
      }.compact
    }

    query_result = execute_query(
      operation_id: CREATE_LABEL_MUTATION.graphql_query_id,
      variables: variables,
      reporting_tags: reporting_tags,
      origin: Platform::ORIGIN_INTERNAL,
    )

    render json: query_result.to_h
  end

  def update
    variables = {
      "input" => {
        "id" => params[:id],
        "color" => params[:color],
        "name" => params[:name],
        "description" => params[:description],
      }.compact
    }

    query_result = execute_query(
      operation_id: UPDATE_LABEL_MUTATION.graphql_query_id,
      variables: variables,
      reporting_tags: reporting_tags,
      origin: Platform::ORIGIN_INTERNAL,
    )

    render json: query_result.to_h
  end

  def destroy
    variables = {
      "input" => {
        "id" => params[:id],
      }
    }

    query_result = execute_query(
      operation_id: DELETE_LABEL_MUTATION.graphql_query_id,
      variables: variables,
      reporting_tags: reporting_tags,
      origin: Platform::ORIGIN_INTERNAL,
    )

    render json: query_result.to_h
  end

  private

  def use_issues_data_router?
    FeatureFlag.vexi.enabled?("issues_data_router", current_user, default: false)
  end

  sig { returns(T::Array[String]) }
  def reporting_tags
    ["app_name:issues"]
  end

  # this is temporary: resolves query hash from the UI manifest until we move to a server-persisted .graphql file
  # not moving it to app/helpers/issues_react_graphql_queries.rb because its temporary
  LABELS_PAGE_QUERY = GraphQLRequest.new(
    name: "RepositoryLabelIndexPageQuery",
    variables: nil,
  )

  CREATE_LABEL_MUTATION = GraphQLRequest.new(
    name: "createRepositoryLabelMutation",
    variables: nil,
  )

  UPDATE_LABEL_MUTATION = GraphQLRequest.new(
    name: "updateLabelMutation",
    variables: nil,
  )

  DELETE_LABEL_MUTATION = GraphQLRequest.new(
    name: "deleteLabelMutation",
    variables: nil,
  )

  class LabelsPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      @route_id
    end

    sig { params(query_result: T.untyped, route_id: String).void }
    def initialize(query_result, route_id = "labelsRoute")
      @query_result = query_result
      @route_id = route_id
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      @query_result.to_h
    end
  end

  def issues_data_router_label_index_handler
    title = "Labels \u00b7 #{current_repository.name_with_display_owner}"

    owner_login = current_repository.owner.display_login
    repo_name = current_repository.name
    page_size = 30

    order_field, order_direction = parse_sort_param(params[:sort])
    page_number = T.let(Integer(params[:page], exception: false), T.nilable(Integer))
    skip = page_number && page_number > 1 ? (page_number - 1) * page_size : 0

    variables = {
      "name" => repo_name,
      "owner" => owner_login,
      "first" => page_size,
      "orderField" => order_field,
      "orderDirection" => order_direction,
      "skip" => skip,
      "query" => params[:q],
    }

    tags = T.must(request).format.json? ? [] : reporting_tags
    query_result = execute_query(
      operation_id: LABELS_PAGE_QUERY.graphql_query_id,
      variables: variables,
      reporting_tags: tags,
      origin: Platform::ORIGIN_INTERNAL,
    )

    payload = LabelsPayload.new(query_result, "labelsRoute")

    respond_to do |format|
      format.html do
        render_react_html(
          app_name: "issues",
          title: title,
          payload: payload,
          nested_payloads: [issues_layout_payload],
          turbo: {
            id: "repo-content-turbo-frame",
            target: "_top",
            action: "advance",
            class: "",
            force: true,
          },
        )
      end
      format.json do
        render_react_json(
          title: title,
          payload: payload,
        )
      end
    end
  end

  VALID_ORDER_FIELDS = { "name" => "NAME", "count" => "ISSUE_COUNT" }.freeze
  VALID_DIRECTIONS = %w[asc desc].freeze

  def issues_layout_payload
    IssuesController::IssuesLayoutPayload.new(
      has_projects_enabled: current_repository.has_projects_enabled?,
      pinned_views_index_page_enabled: PinnedViewsFeature.index_page_enabled?(current_repository, actor: current_user),
      pinned_views_projects_react_enabled: PinnedViewsFeature.projects_react_enabled?(current_repository, actor: current_user),
    )
  end

  # matches the relay variable transformer in packages/issues-react/utils/variable-transformers.ts
  sig { params(sort: T.nilable(String)).returns([String, String]) }
  def parse_sort_param(sort)
    return %w[NAME ASC] if sort.blank?

    option, direction = sort.split("-", 2)
    field = VALID_ORDER_FIELDS[option]
    return %w[NAME ASC] unless field && VALID_DIRECTIONS.include?(direction)

    [field, direction == "asc" ? "ASC" : "DESC"]
  end
end
