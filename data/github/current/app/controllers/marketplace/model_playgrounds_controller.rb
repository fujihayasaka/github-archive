# typed: true
# frozen_string_literal: true

class Marketplace::ModelPlaygroundsController < ApplicationController
  include Marketplace::Models::RenderDependency

  before_action :login_required
  before_action :github_models_required
  before_action :check_user_can_view_model
  before_action :add_models_client_side_feature_flags
  before_action :set_marketplace_context_region

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    connect_src: [GitHub.azure_ai_playground_url, "*.search.windows.net", "*.inference.ai.azure.com"],
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
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

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "marketplace-react"
  end

  def show
    return render_404 unless renderable_model[:model][:task] == "chat-completion"
    return render_404 if renderable_model[:model][:static_model]
    if %w[o1-mini o1-preview].include?(renderable_model[:model][:name]) && current_user && !Copilot::User.new(T.must(current_user)).has_o1_models_access?
      return render_404
    end
    # We're not using SSR for the playground because of flickering issues when loading state from localStorage
    render_model_show(force_ssr: false)
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
