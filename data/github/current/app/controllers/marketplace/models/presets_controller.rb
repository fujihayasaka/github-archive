# typed: true
# frozen_string_literal: true

class Marketplace::Models::PresetsController < ApplicationController
  include Marketplace::Models::PlaygroundDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :github_models_required
  before_action :login_required
  before_action :require_neutron_playground_enabled

  allow_verified_fetch only: [:create, :update, :destroy]
  before_action :parse_json_params, only: [:create, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    if request&.xhr?
      presets = AzureModels::Preset.for_user(current_user).order(:name)
      render json: {
        presets: presets.map(&:json_payload),
        limit_per_user: AzureModels::Preset::LIMIT_PER_USER,
      }, status: :ok
    else
      render_404
    end
  end

  def create
    preset = AzureModels::Preset.create(
      user: current_user,
      name: preset_params[:name],
      description: preset_params[:description],
      private: preset_params[:private].nil? ? true : preset_params[:private],
      parameters: preset_params[:parameters] || {}.to_json,
      conversation_history: conversation_history.to_json,
    )

    if preset.errors.any?
      render json: { error: preset.errors }, status: :unprocessable_entity
    else
      render json: preset.json_payload, status: :created
    end
  end

  def update
    return render json: { error: "Preset not found" }, status: :not_found unless this_preset

    filtered_preset_params = preset_params
    filtered_preset_params[:conversation_history] = conversation_history.to_json # Images should be filtered out at this point but just in case

    if this_preset.update(filtered_preset_params)
      render json: this_preset.json_payload, status: :ok
    else
      render json: { error: this_preset.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    return render json: { error: "Preset not found" }, status: :not_found unless this_preset

    if this_preset.destroy
      render json: { message: "Preset deleted" }, status: :ok
    else
      render json: { error: "Failed to delete preset" }, status: :unprocessable_entity
    end
  end

  private

  def conversation_history
    return [] unless preset_params[:conversation_history]

    history = JSON.parse(preset_params[:conversation_history])
    return history if T.must(current_user).feature_enabled?(:project_neutron_presets_allow_images)

    history.map do |entry|
      next entry if entry["message"].is_a?(String)

      # Images are stored as an array of hashes in "message". We only want to store the text part of it for now.
      if entry["message"].is_a?(Array)
        entry["message"] = entry["message"].select { |m| m["type"] == "text" }
        next entry
      end
    end.compact
  end

  def preset_params
    params.require(:preset).permit(
      :name,
      :description,
      :private,
      parameters: {},
      conversation_history: [:message, { message: [:type, :text, image_url: {}] }, :role, :timestamp]
    ).tap do |allowlisted|
      allowlisted[:parameters] = params[:preset][:parameters].to_json if params[:preset][:parameters]
      allowlisted[:conversation_history] = params[:preset][:conversation_history].to_json if params[:preset][:conversation_history]
    end
  end

  memoize def this_preset
    url_identifier = params[:url_identifier]
    return if url_identifier.blank?

    AzureModels::Preset.for_user(current_user).find_by(url_identifier: params[:url_identifier])
  end

  # TODO: Look into moving this into PlaygroundDependency
  memoize def require_neutron_playground_enabled
    access_result = check_playground_access
    unless access_result.accessible?
      render json: { error: human_readable_reason(access_result.reason) }, status: 404
    end
  end

  def target_for_conditional_access
    current_user
  end
end
