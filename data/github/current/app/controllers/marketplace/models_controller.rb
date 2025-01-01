# typed: true
# frozen_string_literal: true

class Marketplace::ModelsController < ApplicationController
  include GitHub::Memoizer
  include ReactHelper
  include Marketplace::Models::PlaygroundDependency
  include Marketplace::Models::RenderDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:feedback]
  before_action :parse_json_params, only: [:feedback]

  before_action :login_required, only: [:feedback]
  before_action :github_models_required
  before_action :check_user_can_view_model, only: [:show]
  before_action :add_models_client_side_feature_flags, only: [:index, :show]
  before_action :renderable_model_required, only: [:show]
  before_action :set_marketplace_context_region

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
  }.freeze
  before_action :add_csp_exceptions, only: [:show, :index]

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
    only: [:index, :show, :side_model]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :side_model], optional: true

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "marketplace-react"
  end

  def index
    if request&.xhr?
      render json: models.to_json
    else
      render_react_app(
        payload: GitHubModels::Payloads::Index.new(current_user:, models:).call,
        page_data: {
          title: "GitHub Models · GitHub Marketplace",
          description: "Build AI-powered applications with GitHub Models. Experiment with leading AI models, select the best fit for your needs, and get started!",
        },
        ssr: true,
      )
    end
  end

  def show
    render_model_show
  end

  def side_model # rubocop:todo GitHub/UseRestfulActions
    if request&.xhr?
      return render json: { error: "Not found" }, status: :not_found unless is_valid_playground_fetch_request?

      side_model = renderable_side_model(params[:compare_to])
      return render json: { error: "Not found" }, status: :not_found if side_model.nil?

      render json: side_model.to_json
    else
      render_404
    end
  end

  def feedback # rubocop:todo GitHub/UseRestfulActions
    feedback = params[:feedback]

    return render status: 400, json: { message: "Invalid request" } unless feedback.present? && feedback.dig(:model).present?

    GlobalInstrumenter.instrument("github_models.feedback", {
      user: can_provide_additional_feedback? ? current_user : nil,
      feedback_type: feedback.dig(:satisfaction).to_i,
      feedback_choice: feedback.dig(:reasons).reject(&:empty?),
      content: can_provide_additional_feedback? ? feedback.dig(:feedbackText) : nil,
      model: feedback.dig(:model),
      can_be_contacted: can_provide_additional_feedback? ? feedback.dig(:contactConsent) == true : false,
    })

    redirect_to :back
  end

  private

  def renderable_model_required
    # TODO: Add logging for models that are either not found or we're struggling to fetch
    render_404 unless renderable_model.present?
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def can_provide_additional_feedback?
    # If the current user belongs to an entity that is on a Copilot Business or Copilot Enterprise plan, we don't want to send any user data including free text and whether or not they can be contacted by us
    return false if current_user.nil?
    return false if T.must(current_copilot_user).has_cfb_access? || T.must(current_copilot_user).has_cfe_access?
    return false if T.must(current_user).organizations.any? { |org| Copilot::Organization.new(org).copilot_enabled? }
    return false if T.must(current_user).businesses.any? { |bus| Copilot::Business.new(bus).copilot_enabled? }
    true
  end

  def is_valid_playground_fetch_request?
    return false unless current_user.present?
    return false unless params[:compare_to].present?

    true
  end
end
