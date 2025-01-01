# typed: true
# frozen_string_literal: true

class IntegrationListingsController < ApplicationController

  # With the release of Marketplace, this controller is only used in Enterprise,
  # so we don't need to do GitHub.com conditional access checks.
  # cap_bypass:to_fix this controller can also be accessed in proxima
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    index
    feature
    install
    learn_more
  )

  before_action :redirect_to_marketplace, only: :index, if: :marketplace_enabled?
  before_action :redirect_to_marketplace_category, only: :feature, if: :marketplace_enabled?

  layout "site"
  stylesheet_bundle :integrations

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:feature]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:install]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:learn_more]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :learn_more, :install], optional: true

  # Public: The Integrations Directory begins here.
  def index
    feature = IntegrationFeature.at_least_visible.find_by(slug: params[:feature])
    @listings = filtered_listings_for_current_user(feature: feature)

    respond_to do |format|
      format.html do
        if request.xhr? && !pjax?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "integration_listings/list", locals: {
            view: create_view_model(IntegrationListings::IndexView,
              page: current_page,
              query: params[:query],
            )
          }
        else
          render "integration_listings/index"
        end
      end
    end
  end

  # Public: Integration feature page
  def feature # rubocop:todo GitHub/UseRestfulActions
    @feature = IntegrationFeature.at_least_visible.find_by(slug: params[:feature])
    return render_404 unless @feature

    @listings = filtered_listings_for_current_user(feature: @feature)

    render "integration_listings/feature"
  end

  # Public
  def install # rubocop:todo GitHub/UseRestfulActions
    @listing = filtered_listings_for_current_user.find_by_slug(params[:name])
    return render_404 unless @listing

    GitHub.instrument("integration.listing_install_click", {
      dimensions: {
        id: @listing.id,
        cid: cid,
        actor_id: actor_id,
      },
    })

    redirect_to @listing.installation_url
  end

  # Public
  def learn_more # rubocop:todo GitHub/UseRestfulActions
    @listing = filtered_listings_for_current_user.find_by_slug(params[:name])
    return render_404 unless @listing

    GitHub.instrument("integration.listing_learn_more_click", {
      dimensions: {
        id: @listing.id,
        cid: cid,
        actor_id: actor_id,
      },
    })

    session[:last_click_integration_listing_id] = @listing.id
    redirect_to @listing.learn_more_url
  end

  # Internal
  def filtered_listings_for_current_user(feature: nil) # rubocop:todo GitHub/UseRestfulActions
    scope = if feature
      feature.listings.preload(:integration)
    else
      IntegrationListing.preload(:integration)
    end

    scope = if logged_in? && current_user.site_admin?
      scope.draft_and_published
    else
      scope.published
    end

    if params[:query].present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query])}%"
      scope = scope.where("`integration_listings`.`name` LIKE ?", like)
    end

    scope.paginate(page: current_page, per_page: 102) # Waiting for better categories, needs to be a multiple of three.
  end

  # Internal
  def actor_id # rubocop:todo GitHub/UseRestfulActions
    current_user.id if logged_in?
  end

  # Internal
  def cid # rubocop:todo GitHub/UseRestfulActions
    if cookies[:_octo] =~ /\A[^.]+\.[^.]+\.\d+\.\d+\z/
      cookies[:_octo].split(".")[2..3].join(".")
    end
  end

  private

  def marketplace_enabled?
    GitHub.marketplace_enabled?
  end

  def redirect_to_marketplace
    redirect_to marketplace_path
  end

  def redirect_to_marketplace_category
    slug = params[:feature] || ""

    if Marketplace::Category.find_by(slug: slug)
      redirect_to marketplace_category_path(slug)
    elsif IntegrationFeature.at_least_visible.find_by(slug: slug)
      # Per https://github.com/github/github/pull/153511, works with github paths are now deprecated in favor of marketplace.
      redirect_to_marketplace
    end
  end
end
