# typed: true
# frozen_string_literal: true

class Labels::CountsController < AbstractRepositoryController
  include Issues::RateLimitsDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch

  RATE_LIMITS_FEATURES = [
    :issues_rate_limit_circuit_breaker,
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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests

  # GET /:owner/:repo/labels/counts.json?ids[]=gid1&ids[]=gid2
  # Returns issue and pull request counts for the given label global IDs.
  # Executes the same GraphQL query that Relay used client-side, but on the server.
  def index
    global_ids = valid_global_label_ids_for_current_repository(Array(params[:ids]))
    return render json: { data: { nodes: [] } } if global_ids.empty?

    hash = ApplicationController::PersistedGraphqlQueryDependency.persisted_query_hash("LabelCountsQuery")
    result = execute_query(
      operation_id: hash,
      variables: { "nodes" => global_ids },
      origin: Platform::ORIGIN_INTERNAL,
    ).to_h

    if result["errors"].present?
      render json: { errors: result["errors"] }
    else
      render json: { data: result["data"] }
    end
  end

  private

  sig { params(global_ids: T::Array[T.untyped]).returns(T::Array[String]) }
  def valid_global_label_ids_for_current_repository(global_ids)
    label_database_ids = global_ids.filter_map do |global_id|
      next if global_id.blank?

      type_name, node_id = Platform::Helpers::NodeIdentification.from_global_id(global_id.to_s)
      type_name == "Label" ? node_id.to_i : nil
    rescue ArgumentError, Platform::Errors::NotFound
      nil
    end

    return [] if label_database_ids.empty?

    current_repository.labels.where(id: label_database_ids).map(&:global_relay_id)
  end
end
