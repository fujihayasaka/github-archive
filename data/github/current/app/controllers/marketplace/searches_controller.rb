# typed: true
# frozen_string_literal: true

class Marketplace::SearchesController < ApplicationController
  before_action :marketplace_required
  skip_before_action :cap_pagination # page # is capped at 100 in app/controllers/application_controller.rb

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  include ApplicationHelper
  include Platform::Helpers::MarketplaceSearchHelper
  include GitHubModels::RenderDependency

  before_action :add_models_client_side_feature_flags, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:suggested_publishers]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def self.react_bundle_name
    "marketplace-react"
  end

  def show
    context_region_preset :marketplace

    if request&.format&.json?
      return render json: Marketplace::Payloads::Search.new(current_user: current_user, params: params, is_eu_request: helpers.is_eu_request?).call
    end

    if params[:slug].present?
      return redirect_to marketplace_search_path(category: params[:slug])
    end

    if models_result?
      # Workaround, prevent addition of the `· GitHub` suffix for logged-out users
      full_page_title("GitHub Models")
    end

    render_react_app(
      payload: Marketplace::Payloads::Index.new(current_user: current_user, params: params, is_eu_request: helpers.is_eu_request?).call,
      title: !models_result? ? "Marketplace" : nil, # For Models title is set as part of page_data
      page_data: models_result? ? models_page_data : {}
    )
  end

  def suggested_publishers # rubocop:todo GitHub/UseRestfulActions
    app_publishers = app_owners
    action_publishers = action_owners
    stack_publishers = []
    all_publishers = app_publishers | action_publishers

    respond_to do |format|
      format.json do
        render json: {
          "apps": app_publishers,
          "actions": action_publishers,
          "all": all_publishers.sort_by { |publisher| publisher[:login].downcase },
        }
      end
    end
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  # Opting out from conditional access policies is handled in this method
  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def rescue_invalid_cursor
    flash[:error] = "Invalid search query supplied."
    redirect_to marketplace_search_url(type: :apps)
  end

  def app_owners
    marketplace_listings = Marketplace::Listing.publicly_listed
    integration_owner_ids = marketplace_listings.listable_is_integration
                                .joins(" INNER JOIN integrations ON marketplace_listings.listable_id = integrations.id ")
                                .pluck("integrations.owner_id")
    oauth_app_owner_ids = marketplace_listings.where(listable_type: Marketplace::Listing::OAUTH_APPLICATION_TYPE)
                                .joins(" INNER JOIN oauth_applications ON marketplace_listings.listable_id = oauth_applications.id")
                                .pluck("oauth_applications.user_id")
    app_owner_ids = integration_owner_ids | oauth_app_owner_ids
    owner_details(app_owner_ids)
  end

  def action_owners
    action_owner_ids = RepositoryAction.where(state: :listed).includes(:repository).pluck(:owner_id).uniq
    owner_details(action_owner_ids)
  end

  def owner_details(user_ids)
    owners = User.where(id: user_ids).where.not(login: nil).pluck(:login)
    owners.map { |login| { login: login } }.sort_by { |owner| owner[:login].downcase }
  end

  def models_result?
    params[:type] == "models"
  end

  def models_page_data
    {
      description: "Create AI-powered applications with GitHub",
      richweb: {
        title: "GitHub Models",
        url: request&.original_url,
        description: "Create AI-powered applications with GitHub",
        image: image_path("modules/marketplace/models/logo-models.jpg"),
      },
      stafftools: stafftools_models_path,
      canonical_url: request&.original_url
    }
  end
end
