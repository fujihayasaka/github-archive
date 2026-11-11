# typed: true
# frozen_string_literal: true

class ReactSandboxController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:fetch_test]

  before_action :require_feature_flags
  before_action :login_required

  javascript_bundle "ui-version", only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    render_react_app(
      payload: { sandbox_ids: %w[1 2 3] },
      title: "React sandbox",
    )
  end

  def show
    sandbox_id = params[:sandbox_id]
    if sandbox_id == "4"
      render_404
    elsif sandbox_id == "5"
      render status: :internal_server_error, plain: "This is an intentional error"
    elsif sandbox_id == "7"
      redirect_to _react_sandbox_show_path(sandbox_id: 1)
    elsif sandbox_id == "8"
      redirect_to all_pulls_path
    elsif sandbox_id == "partial"
      render "react/sandbox/partial_example"
    elsif sandbox_id == "9"
      render_sandbox_react_app(sandbox_id, "SSR enabled", true)
    elsif sandbox_id == "10"
      render_sandbox_react_app(sandbox_id, "SSR disabled", false)
    elsif sandbox_id == "11"
      render_sandbox_react_app(sandbox_id, "SSR with highly cacheable hint", Alloy::SelectiveSsr::Hints.new(highly_cacheable: true))
    elsif sandbox_id == "12"
      render_sandbox_react_app(sandbox_id, "SSR with no js experience hint", Alloy::SelectiveSsr::Hints.new(no_js_experience: true))
    elsif sandbox_id == "13"
      render_sandbox_react_app(sandbox_id, "SSR with nil hint", nil)
    elsif sandbox_id == "14"
      render_sandbox_react_app(sandbox_id, "SSR with empty hint", Alloy::SelectiveSsr::Hints.new)
    else
      render_react_app(
        payload: {
          greeting: if sandbox_id == "1"
                      "Hello"
                    else
                      sandbox_id == "2" ? "Howdy" : "Moshi moshi"
                    end,
          aliveChannel: GitHub::WebSocket.signed_channel("react_sandbox")
        },
        title: "React sandbox #{sandbox_id}",
      )
    end
  end

  def issues_index # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {},
      title: "React sandbox issues",
    )
  end

  def issues_show # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {},
      title: "React sandbox issue",
    )
  end

  def fetch_test # rubocop:todo GitHub/UseRestfulActions
    # Trigger a live update for testing event flow via alive
    GitHub::WebSocket.notify_react_sandbox_channel("react_sandbox")

    render json: { ok: true }
  end

  def alloy_show # rubocop:todo GitHub/UseRestfulActions
    name = params[:name] || "alloy"
    render_react_app(
      payload: { name: name },
      title: "Alloy SSR",
    )
  end

  def ssr_error # rubocop:todo GitHub/UseRestfulActions
    name = params[:name] || "ssr-error"
    render_react_app(
      payload: { name: name },
      title: "SSR Error",
    )
  end

  def lazy # rubocop:todo GitHub/UseRestfulActions
    name = params[:name] || "lazy"
    render_react_app(
      payload: -> { { name: name } },
      title: "Lazy Payload",
      disable_ssr: true
    )
  end

  def render_sandbox_react_app(sandbox_id, name, ssr) # rubocop:disable GitHub/UseRestfulActions
    render_react_app(
      payload: -> { { name: name } },
      title: "React sandbox #{sandbox_id}",
      force_ssr: ssr,
      disable_ssr: !ssr
    )
  end

  private

  def set_default_nav_breadcrumb
    set_nav_breadcrumb ContextRegion::ReactSandboxCrumb.new
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_flags
    render_404 unless FeatureFlag.vexi.enabled?(:react_sandbox, current_user, default: false)
  end
end
