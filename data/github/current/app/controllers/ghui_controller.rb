# typed: true
# frozen_string_literal: true

class GhuiController < ApplicationController
  layout false

  private

  # Resolves the persisted query hash for a given operation name.
  # Priority:
  #   1. Client-provided queryId param (already a hash)
  #   2. UI manifest serverPersistedQueries (name → hash)
  #   3. Local name_to_hash_manifest via PersistedGraphqlQueryDependency
  def resolve_persisted_query_hash(query_name)
    query_id = params[:queryId]
    return query_id if params[:queryId].present? && query_hash_exists?(query_id)

    query_id = GitHubUI::Manifest.new.server_persisted_queries_manifest&.dig(query_name)
    return query_id if query_id.present? && query_hash_exists?(query_id)

    ApplicationController::PersistedGraphqlQueryDependency.persisted_query_hash(query_name)
  end

  def query_hash_exists?(query_id)
    operation_store = Platform::Schema.operation_store
    result = operation_store.get(
      client_name: Platform::OperationStore::ApplicationRecordBackend::CLIENT_NAME_WILDCARD,
      operation_alias: query_id,
      touch_last_used_at: false
    )
    result.present?
  end

  # Executes a server-persisted GraphQL query by name.
  # Returns the result as a Hash, or renders a 405 and returns nil if the operation name does not match.
  def execute_server_persisted_query(query_name, variables:)
    hash = resolve_persisted_query_hash(query_name)
    result = execute_query(operation_id: hash, variables: variables)

    if result.respond_to?(:query) && result.query.operation_name != query_name
      Rails.logger.error("[execute_server_persisted_query] Operation name mismatch: expected #{query_name.inspect}, got #{result.query.operation_name.inspect}")
      respond_error(:method_not_allowed, "Operation name mismatch")
      return nil
    end

    result.to_h
  end

  def respond_graphql_payload(graphql_response)
    if graphql_response["errors"].present?
      respond_payload({ errors: graphql_response["errors"] })
    else
      respond_payload({ data: graphql_response["data"] })
    end
  end

  def respond_payload(json)
    respond_to do |format|
      format.json do
        render json: json
      end
    end
  end

  def respond_error(status_code, message)
    respond_to do |format|
      format.json do
        render json: { error: message }, status: status_code
      end
    end
  end

  # Parameter validation helpers
  def validate_required_params(*param_names)
    param_names.each do |param_name|
      if params[param_name].blank?
        respond_error(:bad_request, "#{param_name.to_s.humanize} parameter is required")
        return false
      end
    end
    true
  end

  def validate_integer_param(param_name, required: false)
    return true if params[param_name].blank? && !required

    if params[param_name].blank? && required
      respond_error(:bad_request, "#{param_name.to_s.humanize} parameter is required")
      return false
    end

    return true if params[param_name].blank?

    begin
      Integer(params[param_name])
      true
    rescue ArgumentError, TypeError
      respond_error(:bad_request, "#{param_name.to_s.humanize} must be a valid number")
      false
    end
  end

  def parse_integer_param(param_name, default: nil)
    return default if params[param_name].blank?

    begin
      Integer(params[param_name])
    rescue ArgumentError, TypeError
      default
    end
  end
end
