# typed: strict
# frozen_string_literal: true

class Settings::CodingToolsController < ApplicationController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Settings::CodingToolsController#update",
  ]

  depends_on_clusters ApplicationRecord::Mysql1, # Feature flag lookup on show
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:show]
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:update]

  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_feature_enabled

  stylesheet_bundle :settings

  sig { void }
  def show
    coding_tools_settings = T.let(current_coding_tools_settings, T::Hash[String, T::Boolean])
    render "settings/coding_tools/show", locals: {
      coding_tools_settings: coding_tools_settings,
    }
  end

  sig { void }
  def update
    parsed = parse_update_params
    tool = parsed.tool
    enabled = parsed.enabled

    unless ::CodingToolsHelper::KNOWN_TOOLS.include?(tool)
      render json: { success: false, message: "Unknown tool: #{tool}" }, status: :unprocessable_entity
      return
    end

    settings = current_coding_tools_settings
    settings[tool] = enabled

    cookies[:preferred_coding_tools] = {
      value: JSON.generate(settings),
      expires: 1.year.from_now,
      secure: request.ssl?,
      httponly: false,
      same_site: :lax,
      domain: cookie_domain,
    }

    render json: { success: true, tool: tool, enabled: enabled }
  end

  private

  class UpdateParams < T::Struct
    prop :tool, String
    prop :enabled, T::Boolean
  end

  sig { returns(UpdateParams) }
  def parse_update_params
    body = JSON.parse(request.raw_post.presence || "{}")
    tool = (params[:tool] || body["tool"]).to_s
    enabled = (params[:enabled] || body["enabled"]).to_s == "true"
    UpdateParams.new(tool: tool, enabled: enabled)
  rescue JSON::ParserError
    UpdateParams.new(tool: params[:tool].to_s, enabled: params[:enabled].to_s == "true")
  end

  sig { returns(T::Hash[String, T::Boolean]) }
  def current_coding_tools_settings
    raw = cookies[:preferred_coding_tools]
    parsed = if raw.blank?
      {}
    else
      json = JSON.parse(raw)
      json.is_a?(Hash) ? json : {}
    end

    ::CodingToolsHelper::KNOWN_TOOLS.each_with_object({}) do |tool, settings|
      settings[tool] = parsed[tool] == true
    end
  rescue JSON::ParserError
    ::CodingToolsHelper::KNOWN_TOOLS.each_with_object({}) do |tool, settings|
      settings[tool] = false
    end
  end

  sig { void }
  def ensure_feature_enabled
    unless FeatureFlag.vexi.enabled?(:coding_tool_settings, current_user, default: false)
      head :not_found
    end
  end
end
