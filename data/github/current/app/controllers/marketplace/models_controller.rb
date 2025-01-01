# typed: true
# frozen_string_literal: true

class Marketplace::ModelsController < ApplicationController
  extend T::Sig
  include GitHub::Memoizer
  include ReactHelper
  include MarketplaceHelper
  include Marketplace::Models::PlaygroundDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:feedback]
  before_action :parse_json_params, only: [:feedback]

  before_action :marketplace_required
  before_action :add_react_neutron_feature_flags, only: [:index, :show, :playground, :readme]
  before_action :renderable_model_required, only: [:show, :readme]
  before_action :set_marketplace_context_region

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    connect_src: [GitHub.azure_ai_playground_url],
  }.freeze
  before_action :add_csp_exceptions, only: [:show, :playground]

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
    only: [:index, :show, :playground, :readme]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :playground, :readme], optional: true

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
        payload: Marketplace::Payloads::Models::Index.new(current_user:, models:).call,
        title: "Marketplace",
        ssr: true,
      )
    end
  end

  def show
    render_model_show
  end

  def readme # rubocop:todo GitHub/UseRestfulActions
    render_model_show
  end

  def playground # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless renderable_model[:model][:task] == "chat-completion"
    # We're not using SSR for the playground because of flickering issues when loading state from localStorage
    render_model_show(force_ssr: false)
  end

  def feedback # rubocop:todo GitHub/UseRestfulActions
    feedback = params[:feedback]

    GlobalInstrumenter.instrument("github_models.feedback", {
      user: can_provide_additional_feedback? ? current_user : nil,
      feedback_type: feedback.dig(:satisfaction).to_i,
      feedback_choice: feedback.dig(:reasons).reject(&:empty?),
      content: can_provide_additional_feedback? ? feedback.dig(:feedbackText) : nil,
      model: params[:model],
      can_be_contacted: can_provide_additional_feedback? ? feedback.dig(:contactConsent) == true : false,
    })

    redirect_to :back
  end

  private

  def render_model_show(force_ssr: true)
    payload = Marketplace::Payloads::Models::Show.new(
      current_user:,
      miniplayground_icebreaker: params[:p],
      model: renderable_model[:model],
      model_input_schema: renderable_model[:schema]
    ).call

    render_react_app(
      app_payload_generator: -> {
        {
          current_user: {
            login: current_user&.display_login,
            name: current_user&.name,
            avatarUrl: current_user&.primary_avatar_url(80),
            path: user_path(current_user)
          },
        }
      },
      payload: payload,
      title: "Marketplace",
      ssr: force_ssr || !GitHub.flipper[:project_neutron_disable_ssr].enabled?,
      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
      },
    )
  end

  memoize def renderable_model
    model_details(params[:registry], params[:model])
  end

  def renderable_model_required
    # TODO: Add logging for models that are either not found or we're struggling to fetch
    render_404 unless renderable_model.present?
  end

  def set_marketplace_context_region
    context_region_preset :marketplace
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
end
