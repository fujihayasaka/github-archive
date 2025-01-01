# typed: true
# frozen_string_literal: true

class GitHubModels::ModelPlaygroundsController < ApplicationController
  include GitHubModels::RenderDependency

  before_action :login_required
  before_action :github_models_required
  before_action :check_user_can_view_model, only: :show
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
    ApplicationRecord::Iam

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    optional: true

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "github-models"
  end

  def index
    if request&.xhr?
      return render json: low_rate_limit_tier_models(params[:publisher]).to_json if params[:rate_limit_tier] == "low"

      models = models_user.models(sort: :publisher).map { |model| models_user.model_hash(model) }
      return render json: models.to_json
    end
    render_playground_index
  end

  def show
    return render_404 unless model.task == "chat-completion"
    if %w[o1-mini o1-preview o1 o3-mini o3].include?(model.name) && current_user && !Copilot::User.new(T.must(current_user)).has_o1_models_access?
      return render_404
    end
    # We're not using SSR for the playground because of flickering issues when loading state from localStorage
    render_playground_show
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { params(publisher: String).returns(T::Array[GitHubModels::Types::FeaturedModel]) }
  def low_rate_limit_tier_models(publisher)
    priority_models, other_models = models_user.models(sort: :publisher)
      .select { |model| model.rate_limit_tier == "low" }
      .partition { |m| m.publisher == publisher }
    priority_models.concat(other_models).first(3).map(&:to_featured_model)
  end
end
