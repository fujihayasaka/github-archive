# typed: true
# frozen_string_literal: true

class GitHubModels::DetailsController < ApplicationController
  include GitHubModels::RenderDependency

  before_action :github_models_required
  before_action :check_user_can_view_model, only: [:show]
  before_action :add_models_client_side_feature_flags, only: [:show]
  before_action :model_details_json, only: [:show]
  before_action :set_marketplace_context_region

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    connect_src: [GitHub.azure_ai_playground_url, "*.search.windows.net", "*.inference.ai.azure.com", GitHub.models_gateway_url],
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
  }.freeze
  before_action :add_csp_exceptions, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::GitHubModels,
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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Ballast,
    only: [:show], optional: true

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "github-models"
  end

  def show
    render_marketplace_model_show
  end

  private

  def model_details_json
    if request.path.end_with?("/details")
      render json: renderable_side_model(params[:model]).to_json
    end
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def is_valid_playground_fetch_request?
    return false unless current_user.present?
    return false unless params[:compare_to].present?

    true
  end
end
