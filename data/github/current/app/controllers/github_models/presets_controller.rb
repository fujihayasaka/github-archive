# typed: true
# frozen_string_literal: true

class GitHubModels::PresetsController < ApplicationController
  include GitHubModels::PlaygroundDependency
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
    ApplicationRecord::GitHubModels,
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
      presets = GitHubModels.domain.presets.load_payloads(user: current_user)
      render json: {
        presets: presets,
        limit_per_user: GitHubModels.domain.presets.limit_per_user,
      }, status: :ok
    else
      render_404
    end
  end

  def create
    preset = GitHubModels.domain.presets.create(
      user: current_user,
      name: preset_params[:name],
      is_private: preset_params[:private],
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

    success = GitHubModels.domain.presets.update(preset: this_preset, name: preset_params[:name],
      parameters: preset_params[:parameters], is_private: preset_params[:private])

    if success
      render json: this_preset.json_payload, status: :ok
    else
      render json: { error: this_preset.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    return render json: { error: "Preset not found" }, status: :not_found unless this_preset

    if GitHubModels.domain.presets.destroy(this_preset)
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
    slug = params[:url_identifier]
    return if slug.blank?

    GitHubModels.domain.presets.find(user: current_user, slug: slug)
  end

  # TODO: Look into moving this into PlaygroundDependency
  memoize def require_neutron_playground_enabled
    access_result = GitHubModels::PlaygroundAccessResult.for(current_user)
    unless access_result.accessible?
      render json: { error: human_readable_reason(access_result.reason) }, status: 404
    end
  end

  def target_for_conditional_access
    # If the user is not logged in, we return a 401 (:login_required)
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
