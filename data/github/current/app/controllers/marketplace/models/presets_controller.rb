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
      presets = GitHubModels::Preset.for_user(current_user).order(:name)
      render json: {
        presets: presets.map(&:json_payload),
        limit_per_user: GitHubModels::Preset::LIMIT_PER_USER,
      }, status: :ok
    else
      render_404
    end
  end

  def create
    preset = GitHubModels::Preset.create(
      user: current_user,
      name: preset_params[:name],
      private: preset_params[:private].nil? ? true : preset_params[:private],
      parameters: preset_params[:parameters]
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

  def preset_params
    params.require(:preset).permit(
      :name,
      :private,
      parameters: {},
    ).tap do |allowlisted|
      allowlisted[:parameters] = {
        system_prompt: params[:preset][:parameters][:system_prompt] || "",
        chat_prompt: params[:preset][:parameters][:chat_prompt] || "",
      }.to_json if params[:preset][:parameters]
    end
  end

  memoize def this_preset
    url_identifier = params[:url_identifier]
    return if url_identifier.blank?

    GitHubModels::Preset.for_user(current_user).find_by(url_identifier: params[:url_identifier])
  end

  # TODO: Look into moving this into PlaygroundDependency
  memoize def require_neutron_playground_enabled
    access_result = GitHubModels::PlaygroundAccessResult.for(current_user)
    unless access_result.accessible?
      render json: { error: human_readable_reason(access_result.reason) }, status: 404
    end
  end

  def target_for_conditional_access
    current_user
  end
end
