# typed: true
# frozen_string_literal: true

class MarketplacesController < ApplicationController
  before_action :marketplace_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace
  javascript_bundle :"marketplace-react"

  include MarketplaceHelper
  include ReactHelper
  include Platform::Helpers::MarketplaceSearchHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  before_action :add_react_neutron_feature_flags, only: [:show]

  RESULTS_PER_SECTION_PAGE = 10

  def self.react_bundle_name
    "marketplace-react"
  end

  def show
    context_region_preset :marketplace

    GlobalInstrumenter.instrument(Marketplace::Events::HOMEPAGE_VIEW, { viewer_id: current_user&.id })

    respond_to do |format|
      format.json do
        if searching?
          return render json: Marketplace::Payloads::Search.new(current_user: current_user, params: params).call
        else
          return render json: Marketplace::Payloads::Index.new(current_user: current_user, params: params).call
        end
      end
      format.html do
        if params[:slug].present?
          return redirect_to marketplace_search_path(category: params[:slug])
        end

        return render_react_app(
          payload: Marketplace::Payloads::Index.new(current_user: current_user, params: params).call,
          page_data: page_data,
          ssr: true
        )
      end
    end
  end

  # TODO: See if we can remove this action once legacy views are removed
  def show_results # rubocop:todo GitHub/UseRestfulActions
    if request&.xhr?
      search_type = params[:type]
      copilot_app = ActiveModel::Type::Boolean.new.cast(params[:copilot_app])

      search_options = marketplace_search_options
      platform_type = marketplace_search_type(search_type).downcase
      search_results = marketplace_search_query(search_type, copilot_app: copilot_app).execute

      render partial: "marketplace/search_results_fragment", locals: {
          search_results: search_results,
          results_per_section_page: RESULTS_PER_SECTION_PAGE,
          search_query: search_options.query,
          params: search_options.as_params(type: platform_type)
      }
    else
      render_404
    end
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def marketplace_search_query(search_type, copilot_app: false)
    normalizer = lambda do |results|
      results.map! do |h|
        case h["_source"]["search_type"]
        when "marketplace_listing"
          Search::MarketplaceListingResultView.new(h)
        when "repository_action"
          Search::RepositoryActionResultView.new(h)
        when "azure_model"
          Search::AzureModelResultView.new(h)
        end
      end
    end

    Search::Queries::MarketplaceQuery.new \
    current_user: current_user,
    phrase: "",
    type: Search::Queries::MarketplaceQuery::SEARCH_TYPES[search_type],
    offers_free_trial: nil,
    enterprise_compatible: nil,
    verification_state: nil,
    copilot_app: copilot_app,
    context: "marketplace-landing-page",
    highlight: ::Search::OffsetHighlighter.defaults,
    per_page: RESULTS_PER_SECTION_PAGE,
    normalizer: normalizer
  end

  def marketplace_search_options
    Marketplace::SearchOptions.new(
      category_slug: "",
      query: "",
      tool_type: "",
      verification_state: "",
      copilot_app: false,
    )
  end

  def page_data
    {
      title: "Marketplace · Tools to improve your workflow",
      description: "Find the tools that help your team build better, together.",
      container_xl: true,
      stafftools: biztools_marketplace_path,
      selected_link: marketplace_path,
      richweb: {
        title: "GitHub Marketplace: tools to improve your workflow",
        url: request&.original_url,
        description: "Find the tools that help your team build better, together.",
        image: image_path("modules/site/social-cards/marketplace.png"),
      },
      breadcrumb: "Marketplace"
    }
  end
end
