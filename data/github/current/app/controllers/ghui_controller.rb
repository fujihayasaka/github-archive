# typed: true
# frozen_string_literal: true

class GhuiController < ApplicationController
  layout false

  private

  def execute_graphql(query, query_name, variables:)
    # Authorization logic is not properly applied when using ORIGIN_INTERNAL.
    # ORIGIN_API with scopes disabled does correctly enforce authorization.
    # Override to a different value only if authorization happens before that in the request flow.
    origin = Platform::ORIGIN_API

    controller_value = self.class.name&.underscore.sub(/_controller$/, "").gsub(/\//, "_")

    context = {
      viewer: current_user,
      session: T.unsafe(self).session,
      user_session: T.unsafe(self).user_session,
      rails_request: request,
      enforce_conditional_access_via_graphql: true,
      request_access_security_header: request&.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
      origin: origin,
      is_internal_graphql: true,
      cap_filter: T.unsafe(self).cap_filter,
      authenticated_actor_using_web_session: true,
      controller: controller_value,
      action: action_name
    }

    is_get_method = request.get?

    start_time = GitHub::Dogstats.monotonic_time
    result = Platform.execute(
      query,
      target: :internal,
      variables:,
      context: context,
      raise_exceptions: false,
      request_env: request&.env,
      enforce_read_only: is_get_method,
      block_mutations: is_get_method,
    )
    elapsed_ms = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("ghui.request.graphql.dist.time", elapsed_ms, tags: ["query:#{query_name}"])

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
