# typed: true
# frozen_string_literal: true

# A controller that handles executing various requests from Copilot Loops app.
class Copilot::Loops::LoopsClientController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :parse_json_params
  before_action :login_required
  before_action :require_features_enabled

  allow_verified_fetch only: [:create]

  # Accepts a JSON document identifying the operation to be performed by
  # the Loops service along with the necessary arguments. Returns the body
  # and status of the response from the Loops service.
  def create
    client = if feature_enabled_globally_or_for_user?(feature_name: :loops_service_graphql_execution)
      Loops::Client.new(user: current_user, loops_token: get_loops_token)
    else
      copilot_token = request.headers["X-Copilot-Api-Token"]
      Loops::Client.new(user: current_user, copilot_token: copilot_token)
    end

    begin
      res = case params[:operation]
      when "list-loops"
        client.list_loops
      when "list-loop-versions"
        client.list_loop_versions(loop_id: url_param(:loopID))
      when "create-loop"
        client.create_loop(loop_data: params[:loop].permit!.to_h)
      when "delete-loop"
        client.delete_loop(loop_id: url_param(:loopID))
      when "get-loop"
        client.get_loop(loop_id: url_param(:loopID), version_constraint: url_param(:versionConstraint))
      when "update-loop"
        client.update_loop(loop_id: url_param(:loopID), version: url_param(:version), loop_data: params[:loop].permit!.to_h)
      when "create-execution"
        client.create_execution(loop_id: url_param(:loopID), version: url_param(:version), execution_init: params[:executionInit].permit!.to_h)
      when "get-execution"
        client.get_execution(
          loop_id: url_param(:loopID),
          version: url_param(:version),
          execution_id: url_param(:executionID)
        )
      when "update-node-execution"
        client.update_node_execution(
          loop_id: url_param(:loopID),
          version: url_param(:version),
          execution_id: url_param(:executionID),
          node_id: url_param(:nodeID),
          node_execution: params[:nodeExecution].permit!.to_h
        )
      when "share-loop"
        client.share_loop(loop_id: url_param(:loopID))
      when "unshare-loop"
        client.unshare_loop(loop_id: url_param(:loopID))
      when "execute-graphql"
        client.execute_graphql(
          query: params[:query],
          loop_id: url_param(:loopID),
          version: url_param(:version),
          execution_id: url_param(:executionID),
          node_id: url_param(:nodeID)
        )
      else
        return render_error(400, "invalid operation '#{params[:operation]}'")
      end

      if res.status == 502
        GitHub.logger.error("502 Bad Gateway calling loops service.", {
          url: res.env.url.to_s,
          method: res.env.method.to_s,
          headers: res.headers,
          error: res.body
        })
        return render_error(502, "bad gateway")
      end

      render json: res.body, status: res.status
    rescue ArgumentError, ActionController::ParameterMissing => e
      render_error(400, e.message)
    rescue Loops::Client::SuspendedUserError
      render_error(403, "forbidden")
    rescue Loops::Client::SpammyOwnerError
      render_error(404, "not found")
    end
  end

  private

  sig { params(name: Symbol).returns(String) }
  def url_param(name)
    arg = params.require(name)
    raise ArgumentError, "Expected #{name} to be a String, got #{arg.class}" unless arg.is_a? String
    ERB::Util.url_encode(arg)
  end

  def get_loops_token
    token_cache = Loops::TokenCache.new(user_session, saml_for_user)
    token_cache.get_or_create_token
  end

  def require_features_enabled
    render_404 unless features_enabled?
  end

  def render_error(status, message)
    render json: { code: status, message: }, status: status
  end

  def features_enabled?
    current_user.loops_enabled?
  end

  def target_for_conditional_access
    # Currently, all loops are user-owned, and a user may only access loops and executions they own
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
