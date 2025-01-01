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
    # TODO: eventually we should interact with the loops service via a dedicated
    # ruby client gem. This is just the initial throw-it-together version.
    conn = GitHub::FaradayClient.internal("loops", GitHub.loops_url) do |builder|
      builder.headers["X-GitHub-User-ID"] = current_user.id
      builder.headers["X-GitHub-User-Login"] = current_user.display_login
      builder.headers["Content-Type"] = "application/json"
    end

    begin
      case params[:operation]
      when "list-loops"
        res = conn.get("/v1/loops")
      when "list-loop-versions"
        res = conn.get("/v1/loops/#{url_param(:loopID)}/versions")
      when "create-loop"
        body = params[:loop].permit!
        res = conn.post("/v1/loops", body.to_json)
      when "delete-loop"
        res = conn.delete("/v1/loops/#{url_param(:loopID)}")
      when "get-loop"
        res = conn.get("/v1/loops/#{url_param(:loopID)}/v/#{url_param(:versionConstraint)}")
      when "update-loop"
        body = params[:loop].permit!
        res = conn.post("/v1/loops/#{url_param(:loopID)}/v/#{url_param(:version)}", body.to_json)
      when "create-execution"
        body = params[:executionInit].permit!
        res = conn.post("/v1/loops/#{url_param(:loopID)}/v/#{url_param(:version)}/executions", body.to_json)
      when "get-execution"
        res = conn.get("/v1/loops/#{url_param(:loopID)}/v/#{url_param(:version)}/executions/#{url_param(:executionID)}")
      when "update-node-execution"
        body = params[:nodeExecution].permit!
        res = conn.put("/v1/loops/#{url_param(:loopID)}/v/#{url_param(:version)}/executions/#{url_param(:executionID)}/nodes/#{url_param(:nodeID)}", body.to_json)
      when "share-loop"
        res = conn.post("/v1/loops/#{url_param(:loopID)}/share")
      when "unshare-loop"
        res = conn.delete("/v1/loops/#{url_param(:loopID)}/share")
      else
        return head :bad_request
      end

      if res.status == 502
        GitHub.logger.error("502 Bad Gateway calling loops service.", {
          url: res.env.url.to_s,
          method: res.env.method.to_s,
          headers: res.headers,
          error: res.body
        })
      end

      render json: res.body, status: res.status
    rescue ArgumentError, ActionController::ParameterMissing
      head :bad_request
    end
  end

  private

  sig { params(name: Symbol).returns(String) }
  def url_param(name)
    arg = params.require(name)
    raise ArgumentError, "Expected #{name} to be a String, got #{arg.class}" unless arg.is_a? String
    ERB::Util.url_encode(arg)
  end

  def require_features_enabled
    render_404 unless features_enabled?
  end

  def features_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_pipes)
  end

  def target_for_conditional_access
    # Currently, all loops are user-owned, and a user may only access loops and executions they own
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
