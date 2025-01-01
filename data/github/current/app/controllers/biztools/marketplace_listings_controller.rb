# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceListingsController < BiztoolsController

  before_action :marketplace_required
  before_action :verify_single_integratable_specified, only: [:update]
  before_action :cast_boolean_params, only: :update

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Biztools::MarketplaceListingsController#cancel_subscription"
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:hook]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    only: [:finance]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    only: [:approval]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :finance, :show, :index, :hook], optional: true

  def index
    query = params[:query]
    category_slug = params[:category_slug]
    current_state = params[:state] || "VERIFICATION_PENDING_FROM_DRAFT"

    if params[:admin_type] == "Organization"
      organization = Organization.find_by(id: params[:admin_id])
    elsif params[:admin_type] == "User"
      user = User.find_by(id: params[:admin_id])
    end

    listings = Marketplace::Listing.scoped
    listings = listings.unscope(:order).order(updated_at: :desc, id: :desc)
    listings = listings.with_category(category_slug) if category_slug.present?
    listings = listings.matches_name_or_description(query) if query.present?
    listings = listings.editable_by(user) if user.present?
    listings = listings.for_org(organization) if organization.present?
    listings = listings.with_state(current_state.downcase) if current_state.present?
    listings = listings.paginate(page: current_page, per_page: 20)

    unless request.xhr?
      categories = Marketplace::Category.order(:name).not_sponsors_only
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          # Pagination
          render partial: "biztools/marketplace_listings/listings",
                 locals: { listings: listings, current_state: current_state,
                           category_slug: category_slug, query: query }
        else
          render "biztools/marketplace_listings/index",
            locals: { listings: listings, query: query, category_slug: category_slug,
                      current_state: current_state, categories: categories,
                      user: user, organization: organization }
        end
      end
    end
  end

  def edit
    listing = Marketplace::Listing.find_by(slug: params[:listing_slug])
    return render_404 unless listing

    user_id = listing.owner&.id
    integration = Integration.find_by(id: listing.listable_id) if listing.listable_is_integration?
    integrations = listable_integrations_for(user_id: user_id, integration: integration)
    oauth_app = OauthApplication.find_by(id: listing.listable_id) if listing.listable_is_oauth_application?
    oauth_apps = listable_oauth_apps_for(user_id: user_id, oauth_app: oauth_app)
    categories = Marketplace::Category.order(:name).not_sponsors_only

    respond_to do |format|
      format.html do
        render "biztools/marketplace_listings/edit",
          locals: { listing: listing, oauth_apps: oauth_apps,
                    integrations: integrations, categories: categories }
      end
    end
  end

  def show
    listing = Marketplace::Listing.find_by(slug: params[:listing_slug])

    return render_404 unless listing

    respond_to do |format|
      format.html do
        render "biztools/marketplace_listings/show", locals: { listing: listing }
      end
    end
  end

  def approve # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find(params[:listing_id])

    if listing.can_approve?
      T.unsafe(listing).approve!(current_user, params[:message])
    else
      flash[:error] = "Listing cannot be approved."
    end

    redirect_to(marketplace_listing_path(params[:slug]))
  end

  def approve_creator # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find(params[:listing_id])

    if listing.can_approve?
      T.unsafe(listing).approve_creator!(current_user, params[:message])
    else
      flash[:error] = "Listing cannot be approved."
    end

    redirect_to(marketplace_listing_path(params[:slug]))
  end

  def move_to_verified # rubocop:todo GitHub/UseRestfulActions
    unless current_user.can_admin_marketplace_listings?
      flash[:error] = "#{current_user} does not have permission to approve the listing."
      return redirect_to(marketplace_listing_path(params[:slug]))
    end

    listing = Marketplace::Listing.find_by(slug: params[:slug])
    return render_404 unless listing

    unless listing.can_move_to_verified?
      flash[:error] = "Listing can not be moved to verified state."
      return redirect_to(marketplace_listing_path(params[:slug]))
    end


    # todo: Sorbet complains about move_to_verified! not accepting any arguments, which seems
    # incorrect based on real-world usage, so we should update the workflow Tapioca compiler
    # to support passing arguments to these generated methods
    T.unsafe(listing).move_to_verified!(current_user, params[:message])
    redirect_to(marketplace_listing_path(params[:slug]))
  end

  def reject # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find(params[:listing_id])
    state = params[:state].to_s.downcase
    mark_spam = ActiveModel::Type::Boolean.new.cast(params[:mark_spam])

    case state
    when "draft"
      if listing.can_redraft?
        T.unsafe(listing).redraft!(current_user, params[:message])
        flash[:notice] = "Listing moved to draft state."
      else
        flash[:error] = "Listing cannot be moved to draft state."
      end
    when "unverified"
      if listing.can_redraft?
        T.unsafe(listing).redraft!(current_user, params[:message])
        flash[:notice] = "Listing moved to unverified state."
      else
        flash[:error] = "Listing cannot be moved to unverified state."
      end
    when "rejected"
      if listing.can_reject?
        T.unsafe(listing).reject!(current_user, params[:message])
        flash[:notice] = "Listing rejected."
      else
        flash[:error] = "Listing cannot be rejected."
      end
    else
      flash[:error] = "Cannot reject a listing by moving it to the '#{state}' state."
    end

    if mark_spam
      redirect_to(stafftools_user_administrative_tasks_path(listing.owner))
    else
      redirect_to(marketplace_listing_path(params[:slug]))
    end
  end

  def delist # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find(params[:listing_id])

    if listing.can_delist?
      T.unsafe(listing).delist!(current_user, params[:message])
    else
      flash[:error] = "Marketplace listing cannot be delisted."
    end

    redirect_to(marketplace_listing_path(params[:slug]))
  end

  def update
    listing = Marketplace::Listing.find_by!(slug: params[:listing_slug])
    inputs =  marketplace_listing_params

    if (id = inputs[:oauthApplicationDatabaseID]).present?
      inputs[:oauthApplicationDatabaseID] = id.to_i
    end

    [:featuredAt, :oauthApplicationDatabaseID, :appID].each do |field|
      inputs[field] = nil if inputs[field].blank?
    end

    if inputs[:featuredAt].present?
      inputs[:featuredAt] = Time.zone.parse(inputs[:featuredAt])
    end

    inputs = inputs.transform_keys(&:underscore)

    unless Marketplace::Public::update_listing(listing, inputs: inputs, viewer: current_user)
      message = listing.errors.full_messages.to_sentence
      flash[:error] = message
      return redirect_to(biztools_edit_marketplace_listing_path(params[:listing_slug]))
    end

    redirect_to biztools_marketplace_listing_path(params[:listing_slug])
  end

  def feature # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(slug: params[:listing_slug])
    listing.featured_at = Time.zone.now
    updated_featured_at = listing.featured_at_changed?

    if listing.save
      listing.instrument_featured_at_changed(actor: current_user) if updated_featured_at
      respond_to do |format|
        format.html do
          if request.xhr?
            render partial: "biztools/marketplace_listings/listing", locals: { listing: listing }
          else
            redirect_to(biztools_edit_marketplace_listing_path(params[:listing_slug]))
          end
        end
      end
    else
      error = "Could not update the listing: #{listing.errors.full_messages.join(", ")}"
      render json: { error: error }, status: :unprocessable_entity
    end
  end

  def unfeature # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(slug: params[:listing_slug])
    listing.featured_at = nil
    updated_featured_at = listing.featured_at_changed?

    if listing.save
      listing.instrument_featured_at_changed(actor: current_user) if updated_featured_at
      respond_to do |format|
        format.html do
          if request.xhr?
            render partial: "biztools/marketplace_listings/listing", locals: { listing: listing }
          else
            redirect_to(biztools_edit_marketplace_listing_path(params[:listing_slug]))
          end
        end
      end
    else
      error = "Could not update the listing: #{listing.errors.full_messages.join(", ")}"
      render json: { error: error }, status: :unprocessable_entity
    end
  end

  def reindex # rubocop:todo GitHub/UseRestfulActions
    integration = Marketplace::Listing.find(params[:listing_id])
    if params[:reindex] == "add"
      Search.add_to_search_index("marketplace_listing", integration.id)
      flash[:notice] = "App added to the search index."
    elsif params[:reindex] == "remove"
      RemoveFromSearchIndexJob.perform_later("marketplace_listing", integration.id)
      flash[:notice] = "App removed from the search index."
    end

    redirect_to(biztools_marketplace_listing_path(integration.slug))
  end

  def hook # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(slug: params[:listing_id])
    hook = listing.webhook

    return render_404 unless hook.present?

    render(
      "biztools/marketplace_listings/hook",
      locals: { listing: listing, hook: hook, hook_deliveries_query: params[:deliveries_q] }
    )
  end

  def test_hook # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(slug: params[:listing_slug])
    hook = listing.webhook

    return render_404 unless hook.present?

    begin
      hook.ping
      flash[:notice] = "A ping payload has been sent to test the webhook. Please check the delivery status below. Due to latency with testing the webhook, the page may have to be refreshed for the result to be shown."
    rescue => e # rubocop:todo Lint/GenericRescue
      flash[:error] = "There was an error testing the hook: #{e.message}"
    end

    redirect_to biztools_marketplace_listing_hook_path(
      listing.slug,
    )
  end

  sig { void }
  def finance # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(slug: params[:listing_id])
    subscriptions = listing.subscription_items.includes(plan_subscription: :user)
    subscription_count = subscriptions.count
    subscriptions = subscriptions.paginate(page: current_page, per_page: 25)

    render(
      "biztools/marketplace_listings/finance",
      locals: { listing: listing, subscriptions: subscriptions, subscription_count: subscription_count }
    )
  end

  sig { void }
  def approval # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless user_feature_enabled?(:marketplace_listing_approval_page)
    listing = Marketplace::Listing.find_by!(slug: params[:listing_id])

    render("biztools/marketplace_listings/approval", locals: { listing: listing })
  end

  sig { void }
  def cancel_subscriptions # rubocop:todo GitHub/UseRestfulActions
    listing = Marketplace::Listing.find_by!(id: params[:listing_id])

    if listing.archived?
      MarketplaceCancelSubscriptionsJob.perform_later(T.must(listing.id))
      flash[:notice] = "Queued job to cancel all subscriptions to #{listing.name}."
    else
      flash[:notice] = "Cannot cancel subscriptions for an active listing. Please archive the listing first."
    end
    redirect_to(biztools_marketplace_listing_finance_path(listing.slug))
  end

  private

  def marketplace_listing_params
    params.require(:marketplace_listing).
      permit(:primaryCategoryName, :secondaryCategoryName,
             :oauthApplicationDatabaseID, :appID, :featuredAt,
             :hasDirectBilling, :isByGithub, :isCopilotApp, filterCategories: [])
  end

  def verify_single_integratable_specified
    mkt_params = params[:marketplace_listing]
    if mkt_params[:appID].present? && mkt_params[:oauthApplicationDatabaseID].present?
      flash[:error] = "Cannot specify both an OAuth application and an integration."
      redirect_to biztools_edit_marketplace_listing_path(params[:listing_slug])
    end
  end

  def listable_integrations_for(user_id:, integration:)
    integrations = Integration.not_in_marketplace.where(owner_id: user_id)
    if integration
      integrations = integrations.where("integrations.id <> ?", integration.id)
    end
    integrations
  end

  def listable_oauth_apps_for(user_id:, oauth_app:)
    oauth_apps = OauthApplication.not_in_marketplace.where(user_id: user_id)
    if oauth_app
      oauth_apps = oauth_apps.where("oauth_applications.id <> ?", oauth_app.id)
    end
    oauth_apps
  end

  def cast_boolean_params
    # we need to cast the value sent in the request to an actual boolean
    # otherwise GraphQL rejects it
    %i(hasDirectBilling isByGithub isCopilotApp).each do |attr|
      if (bool_param = params.dig(:marketplace_listing, attr)).present?
        params[:marketplace_listing][attr] = ActiveModel::Type::Boolean
          .new.cast(bool_param)
      end
    end
  end
end
