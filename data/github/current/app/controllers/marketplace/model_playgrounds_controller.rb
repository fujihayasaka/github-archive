# typed: true
# frozen_string_literal: true

class Marketplace::ModelPlaygroundsController < ApplicationController
  include Marketplace::Models::RenderDependency

  before_action :login_required, only: :show
  before_action :github_models_required
  before_action :check_user_can_view_model, only: :show
  before_action :require_feature, only: :show
  before_action :add_models_client_side_feature_flags
  before_action :set_marketplace_context_region

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    connect_src: [
      GitHub.azure_ai_playground_url,
      GitHub.models_gateway_url,
      "*.search.windows.net",
      "*.inference.ai.azure.com",
    ],
    img_src: [
      SecureHeaders::PolicyManagement::DATA_PROTOCOL,
      "*.blob.core.windows.net",
    ],
  }.freeze
  before_action :add_csp_exceptions

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
    ApplicationRecord::Iam

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    optional: true

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "marketplace-react"
  end

  def index
    if request&.xhr?
      return render json: low_rate_limit_tier_models(params[:publisher]).to_json if params[:rate_limit_tier] == "low"
      return render json: models_user.models(sort: :publisher).to_json
    end
    return redirect_to :marketplace_models_catalog unless logged_in?
    render_playground_index
  end

  def show
    return render_404 unless catalog_item.task == "chat-completion"
    if %w[o1-mini o1-preview o1 o3-mini].include?(catalog_item.name) && current_user && !Copilot::User.new(T.must(current_user)).has_o1_models_access?
      return render_404
    end
    # We're not using SSR for the playground because of flickering issues when loading state from localStorage
    render_model_show(force_ssr: false)
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def require_feature
    if request.path.end_with?("/prompt")
      has_feature = feature_enabled_globally_or_for_current_user?(:github_models_prompt_editor) ||
        feature_enabled_globally_or_for_current_user?(:github_models_prompt_evals)
      render_404 unless has_feature
    elsif request.path.end_with?("/evals")
      render_404 unless feature_enabled_globally_or_for_current_user?(:github_models_prompt_evals)
    end
  end

  sig { params(publisher: String).returns(T::Array[GitHubModels::Types::FeaturedModel]) }
  def low_rate_limit_tier_models(publisher)
    priority_models, other_models = models_user.models(sort: :publisher)
      .select { |model| model[:rate_limit_tier] == "low" }
      .partition { |m| m[:publisher] == publisher }
    priority_models.concat(other_models).first(3)
  end
end
