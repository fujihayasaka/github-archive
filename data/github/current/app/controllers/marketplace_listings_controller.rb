# typed: true
# frozen_string_literal: true

class MarketplaceListingsController < ApplicationController


  before_action :marketplace_required
  before_action :login_required, only: [:edit, :new, :create, :manage, :preview]
  before_action :this_marketplace_listing_required, only: [:edit, :edit_description, :edit_contact_info, :redraft, :screenshots, :show, :update]
  before_action :this_marketplace_listing_edit_required, only: [:edit, :edit_description, :edit_contact_info, :update]
  before_action :this_marketplace_listing_admin_required, only: :redraft
  before_action :sudo_filter, only: [:edit, :edit_description, :edit_contact_info]
  before_action :require_xhr, only: :screenshots
  before_action :set_suggested_target_id_cookie, only: :show
  before_action :set_repository_ids_cookie, only: :show
  before_action :dismiss_dashboard_copilot_extensions_docker_nudge, only: :show

  before_action :add_csp_exceptions, only: [:edit, :show, :edit_description]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:edit_contact_info]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:edit_description]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:free_trials]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:manage]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:new_with_integratable]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:screenshots]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :new, :edit, :free_trials, :new_with_integratable, :edit_description, :manage, :edit_contact_info],
    optional: true

  CSP_EXCEPTIONS = {
    connect_src: [
      # todo: Sorbet believes that `storage_s3_hostname` does not exist on these classes, so for now
      # to enable typing we are just leaving this as unsafe
      T.unsafe(Marketplace::ListingScreenshot).storage_s3_hostname,
      T.unsafe(Marketplace::ListingImage).storage_s3_hostname
    ],
  }

  GITHUB_APP_TYPE       = "app".freeze
  OAUTH_APP_TYPE        = "oauth_app".freeze
  PERMITTED_APP_TYPES   = [GITHUB_APP_TYPE, OAUTH_APP_TYPE].freeze

  rescue_from PlatformHelper::InvalidCursorError, with: :render_404

  include AvatarHelper

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace
  stylesheet_bundle :settings

  # Public: The Marketplace free trials page
  def free_trials # rubocop:todo GitHub/UseRestfulActions
    categories = Marketplace::Category.order(:name).not_sponsors_only.navigation_visible.with_listings
    manageable_listings_count = logged_in? ? Marketplace::Listing.editable_by(current_user).size : 0
    listings = Marketplace::Listing.publicly_listed.
      with_free_trial(state: :published).
      order(id: :desc).
      first(30)

    # Prefill async fields on each listing
    promises = Promise.all(listings.flat_map do |listing|
      [
        listing.async_owner,
        listing.async_cached_installation_count,
        listing.async_is_recommended?,
      ]
    end).sync

    respond_to do |format|
      format.html do
        render "marketplace_listings/free_trials", locals: {
          listings: listings,
          categories: categories,
          manageable_listings_count: manageable_listings_count,
        }
      end
    end
  end

  def self.react_bundle_name
    "marketplace-react"
  end

  # Public: Integration detail page
  def show
    context_region_preset :marketplace_apps

    GlobalInstrumenter.instrument(Marketplace::Events::LISTING_VIEW, {
      viewer_id: current_user&.id,
      listing: this_marketplace_listing,
    })

    if params[:plan_id].present?
      return redirect_to marketplace_listing_path(listing_slug: params[:listing_slug], anchor: "pricing-and-setup")
    end

    this_marketplace_listing.listing_plans.each do |plan|
      add_csrf_token(marketplace_order_purchase_path(listing_slug: this_marketplace_listing.slug, plan_id: plan.global_relay_id), :post) if this_marketplace_listing.copilot_app?
      add_csrf_token(marketplace_order_upgrade_path(listing_slug: this_marketplace_listing.slug, plan_id: plan.global_relay_id), :post)
    end

    this_marketplace_listing.listing_plans.where(direct_billing: true).each do |plan|
      add_csrf_token(marketplace_order_purchase_path(listing_slug: this_marketplace_listing.slug, plan_id: plan.global_relay_id), :post)
    end

    render_react_app(
      payload: Marketplace::Payloads::ShowApp.new(marketplace_listing: this_marketplace_listing, current_user: current_user).call,
      page_data: page_data,
    )
  end

  NEW_QUERY_PAGE_SIZE = 5

  def new
    excluded_org_ids = cap_filter.unauthorized_resource_ids(T.must(current_user).organizations)

    oauth_apps = OauthApplication.adminable_by(current_user).
      not_in_marketplace.
      where.not(user_id: excluded_org_ids).
      order("oauth_applications.updated_at DESC, oauth_applications.id DESC").
      paginate(page: current_page(:oauth_cursor), per_page: NEW_QUERY_PAGE_SIZE)

    apps = Integration.adminable_by(current_user).
      not_for_github_connect.
      not_in_marketplace.
      where(visibility: :public_visibility).
      where.not(owner_id: excluded_org_ids).
      order("integrations.updated_at DESC, integrations.id DESC").
      paginate(page: current_page(:app_cursor), per_page: NEW_QUERY_PAGE_SIZE)

    actions = RepositoryAction.adminable_by(current_user).
      not_in_marketplace.
      joins(:repository).
      where.not(repositories: { owner_id: excluded_org_ids }).
      order("repository_actions.updated_at DESC, repository_actions.id DESC").
      paginate(page: current_page(:action_cursor), per_page: NEW_QUERY_PAGE_SIZE)

    GlobalInstrumenter.instrument(Marketplace::Events::CREATE_EXTENSION_VIEW, { viewer_id: current_user&.id })

    respond_to do |format|
      format.html do
        if T.must(request).xhr?
          if params[:oauth_cursor]
            render partial: "marketplace_listings/oauth_applications", locals: { oauth_apps: oauth_apps }
          elsif params[:app_cursor]
            render partial: "marketplace_listings/integrations", locals: { apps: apps }
          elsif params[:action_cursor]
            render partial: "marketplace_listings/actions", locals: { actions: actions }
          end
        else
          render "marketplace_listings/new", locals: {
            oauth_apps: oauth_apps,
            apps: apps,
            actions: actions,
          }
        end
      end
    end
  end

  def new_with_integratable # rubocop:todo GitHub/UseRestfulActions
    integratable = find_integratable(params[:type], params[:id])

    unless integratable
      return render_404
    end

    if (listing = integratable.marketplace_listing).present?
      if listing.adminable_by?(current_user)
        return redirect_to edit_marketplace_listing_path(listing)
      end

      return render_404
    end

    unless PERMITTED_APP_TYPES.include?(params[:type])
      flash[:error] = "You must specify which GitHub App or OAuth application you'd like to list."
      return redirect_to marketplace_path
    end

    return render_404 unless integratable.adminable_by?(current_user)

    respond_to do |format|
      format.html do
        render "marketplace_listings/new_with_integratable",
          locals: { category_names: integratable_category_names, integratable: integratable, integratable_type: params[:type],
                    form_data: {} }
      end
    end
  end

  def create
    integratable = integratable_for_creation
    return render_404 unless integratable.present? && integratable.adminable_by?(current_user)

    inputs = input_for_creation.transform_keys(&:underscore).merge(listable: integratable)
    listing = Marketplace::Public::create_listing(inputs: inputs, viewer: current_user)

    if listing.copilot_app?
      listing.find_or_create_free_plan
    end

    if listing.errors.any?
      flash[:error] = "Could not create a Marketplace listing:  #{listing.errors.full_messages.join(", ")}"
      type = integratable.is_a?(OauthApplication) ? OAUTH_APP_TYPE : GITHUB_APP_TYPE

      return render "marketplace_listings/new_with_integratable",
        locals: { category_names: integratable_category_names, integratable: integratable,
                  integratable_type: type, form_data: input_for_creation }
    end

    flash[:notice] = "A draft of your Marketplace listing has been saved. You can " +
                     "customize your listing further."
    redirect_to edit_marketplace_listing_path(listing.slug)
  end

  def edit
    view = create_view_model(Marketplace::Listings::OnboardingPageView, { listing: this_marketplace_listing })
    # Hydro instrumentation
    GlobalInstrumenter.instrument("marketplace.onboarding_progress", view.metrics_progress_payload.merge(actor: current_user))

    agreement = Marketplace::Agreement.latest_for_integrators if logged_in?

    respond_to do |format|
      format.html do
        render "marketplace_listings/edit", locals: { view: view, marketplace_listing: this_marketplace_listing, agreement: agreement }
      end
    end
  end

  def edit_description # rubocop:todo GitHub/UseRestfulActions
    marketplace_categories = Marketplace::Category
                              .select(:name)
                              .order(:name)
                              .not_sponsors_only
                              .where(acts_as_filter: false)

    respond_to do |format|
      format.html do
        render "marketplace_listings/edit/description", locals: {
            marketplace_listing: this_marketplace_listing,
            marketplace_categories: marketplace_categories,
            description_body: description_body,
          }
      end
    end
  end

  def edit_contact_info # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render "marketplace_listings/edit/contact_info", locals: { marketplace_listing: this_marketplace_listing }
      end
    end
  end

  def update
    listing = this_marketplace_listing
    inputs = marketplace_params.transform_keys(&:underscore)

    unless Marketplace::Public::update_listing(listing, inputs: inputs, viewer: current_user)
      message = "Could not update the listing: #{listing.errors.full_messages.join(", ")}"

      if T.must(request).xhr?
        return render json: { error: message }, status: :unprocessable_entity
      else
        flash[:error] = message
        return redirect_to(edit_marketplace_listing_path(params[:listing_slug]))
      end
    end

    path = update_redirect_path(listing)

    if T.must(request).xhr?
      render json: { path: path, bgcolor: listing.bgcolor, short_description: listing.short_description }
    else
      redirect_to path
    end
  end

  def redraft # rubocop:todo GitHub/UseRestfulActions
    slug = params[:listing_slug]

    unless this_marketplace_listing.can_redraft?
      flash[:error] = "Marketplace listing cannot be moved to draft state."
      return redirect_to(marketplace_listing_path(slug))
    end

    this_marketplace_listing.redraft!(current_user)

    flash[:notice] = "Your listing is no longer awaiting review from GitHub staff. You may " +
                     "make additional changes and resubmit when ready."
    redirect_to edit_marketplace_listing_path(slug)
  end

  def screenshots # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "marketplace_listings/edit/product_screenshots",
               locals: { marketplace_listing: this_marketplace_listing }
      end
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    markdown = params[:text]
    context = T.let({ base_url: base_url, current_user: current_user }, T::Hash[Symbol, T.untyped])

    html = GitHub.dogstats.time("markdown", tags: ["action:preview"]) do
      GitHub::Goomba::MarkdownPipeline.to_html(markdown, context)
    end

    render html: html
  end

  def manage # rubocop:todo GitHub/UseRestfulActions
    listings = Marketplace::Listing.editable_by(current_user).
      order(id: :desc).
      first(10)

    actions = RepositoryAction.discoverable.
      with_state(:listed).
      joins(:repository).
      where("repositories.id IN (?)", T.must(current_user).associated_repository_ids(min_action: :write)). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      order("repository_actions.created_at desc, repository_actions.id desc").
      preload(:repository).
      first(10)

    if (listings.size + actions.size) > 1
      respond_to do |format|
        format.html do
          render "marketplace_listings/manage", locals: { listings: listings, actions: actions }
        end
      end
    elsif listings.size == 1
      listing = T.must(listings.first)

      if listing.allowed_to_edit?(current_user)
        redirect_to edit_marketplace_listing_path(listing.slug)
      else
        redirect_to marketplace_listing_path(listing.slug)
      end
    elsif actions.size == 1
      action = T.must(actions.first)
      redirect_to marketplace_action_path(action.slug)
    else
      redirect_to new_marketplace_listing_path
    end
  end

  private

  def marketplace_params
    return {} unless params[:marketplace_listing]
    input = params[:marketplace_listing].
              permit(
                :appID,
                :companyUrl,
                :documentationUrl,
                :extendedDescription,
                :financeEmail,
                :fullDescription,
                :heroCardBackgroundImageDatabaseID,
                :installationUrl,
                :isLightText,
                :marketingEmail,
                :name,
                :oauthApplicationID,
                :pricingUrl,
                :primaryCategoryName,
                :privacyPolicyUrl,
                :secondaryCategoryName,
                :securityEmail,
                :shortDescription,
                :slug,
                :statusUrl,
                :supportUrl,
                :demoUrl,
                :onboardingUrl,
                :technicalEmail,
                :termsOfServiceUrl,
                :logoBackgroundColor,
                supportedLanguageNames: [],
              )

    if input[:isLightText]
      input[:isLightText] = input[:isLightText] == "true"
    end

    if input[:heroCardBackgroundImageDatabaseID]
      input[:heroCardBackgroundImageDatabaseID] = input[:heroCardBackgroundImageDatabaseID].to_i
    end

    input
  end

  def description_body
    <<~BODY
      ## Capabilities
      <!-- Describe key features and functionalities of your Copilot Extension. What can it do? -->
      - Automate code review
      - Real-time debugging assistance
      - Reference docs in your [example] organization account

      ## Benefits
      <!-- What problems does it address? How does it improve the developer workflow? -->
      - **Code quality:** Provides instant feedback on best practices and error detection.
      - **Streamline Debugging:** Automates debugging, reducing manual code reviews.
      - **Query Knowledge Bases:** Access public and private knowledge bases seamlessly.

      ## Getting Started
      <!-- Provide a quick overview of how to start using the extension. Include any prerequisites. -->
      **Requirements:**
      - **Plan:** [Specify if a paid plan is necessary]
      - **User Permissions:** [Detail the required access levels]
      - **Availability:** [Specify if it's in Beta, GA, and/or behind a waitlist]
      - **Onboarding Video:** [If set-up is complex, we recommend providing a link to a public onboarding video]

      **Setup Process:**
      1. [First key step]
      2. [Second key step]
      3. [Third key step]

      ## Example Prompts
      <!-- List 3-6 example prompts that showcase your extension's capabilities and potential use cases. -->
      Try these prompts with `@example-agent`:
      - "Review my project's code for best practices"
      - "Debug the code and highlight errors"
      - "Summarize our docs page about the QA testing process"
    BODY
  end

  def ip_allowlist_enforceable
    return :no if action_name == "show"
    :yes
  end

  # Opting out from or enforcing conditional access policies is handled in this method
  def external_conditional_access_policy_enforceable
    return :no if action_name == "show"
    super
  end

  def require_active_external_identity_session?
    return false if action_name == "show"
    true
  end

  def two_factor_enforceable
    return :no if action_name == "show"
    :yes
  end

  def target_for_conditional_access
    if action_name == "create"
      integratable = integratable_for_creation
      return :no_target_for_conditional_access unless integratable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      integratable.owner
    else
      listing = Marketplace::Listing.find_by(slug: params[:listing_slug])
      return :no_target_for_conditional_access unless listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      listing.owner
    end
  end

  def input_for_creation
    args = marketplace_params
    input = args.slice(:name, :shortDescription, :fullDescription, :privacyPolicyUrl,
                       :supportedLanguageNames, :supportUrl, :primaryCategoryName, :installationUrl)

    if args[:oauthApplicationID]
      input[:oauthApplicationID] = args[:oauthApplicationID].to_i
    elsif args[:appID]
      input[:appID] = args[:appID].to_i
    end

    input
  end

  def integratable_for_creation
    input = input_for_creation

    if input[:oauthApplicationID]
      OauthApplication.find(input[:oauthApplicationID])
    elsif input[:appID]
      Integration.find(input[:appID])
    end
  end

  sig { params(type: T.untyped, id: T.untyped).returns(T.nilable(T.any(OauthApplication, Integration))) }
  def find_integratable(type, id)
    if type == OAUTH_APP_TYPE
      OauthApplication.find(id)
    elsif type == GITHUB_APP_TYPE
      Integration.find(id)
    end
  end

  def redirect_to_billing_settings_with_delisted_error(marketplace_listing:, subscription_item:)
    if subscription_item.present?
      flash[:error] = "#{marketplace_listing.name} has been removed from GitHub Marketplace. You can cancel your subscription below."
    else
      flash[:error] = "#{marketplace_listing.name} has been removed from GitHub Marketplace. You can cancel your subscription by navigating to your organization's billing settings."
    end

    redirect_to settings_user_billing_path
  end

  def update_redirect_path(listing)
    # Generates the correct url based on where the user is in the edit flow
    if params[:page] == "description"
      return edit_description_marketplace_listing_path(listing.slug)
    end
    if params[:page] == "contact"
      return edit_contact_info_marketplace_listing_path(listing.slug)
    end

    edit_marketplace_listing_path(listing.slug)
  end

  def set_suggested_target_id_cookie
    return unless params[:suggested_target_id].present?

    json_val = JSON.generate(params[:suggested_target_id])
    cookies[:marketplace_suggested_target_id] = { value: json_val, expires: 1.hour }
  end

  def set_repository_ids_cookie
    return unless params[:repository_ids].present?

    json_val = JSON.generate(params[:repository_ids])
    cookies[:marketplace_repository_ids] = { value: json_val, expires: 1.hour }
  end

  memoize def this_marketplace_listing
    slug = params[:listing_slug]
    return if slug.blank?

    Marketplace::Listing.find_by(slug: slug)
  end
  helper_method :this_marketplace_listing

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing&.can_viewer_see?(current_user)
  end

  def this_marketplace_listing_edit_required
    render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)
  end

  def this_marketplace_listing_admin_required
    render_404 unless this_marketplace_listing.adminable_by?(current_user)
  end

  def integratable_category_names
    Marketplace::Category.order(:name).not_sponsors_only.where(acts_as_filter: false).pluck(:name)
  end

  def page_data
    return {} unless this_marketplace_listing
    listing = T.cast(this_marketplace_listing, Marketplace::Listing)
    owner = listing.owner
    if owner.respond_to?(:hide_from_user?) && T.unsafe(owner).hide_from_user?(current_user)
      owner = nil
    end
    screenshots = listing.screenshots.order(:sequence).first(Marketplace::ListingScreenshot::SCREENSHOT_LIMIT_PER_LISTING)
    default_image = screenshots.any? ? T.must(screenshots.first).storage_external_url(current_user) : owner&.primary_avatar_url(400)
    og_image = listing.og_image_url ? listing.og_image_url : default_image

    {
      title: "#{listing.name} · GitHub Marketplace",
      description: listing.short_description,
      container_xl: true,
      selected_link: marketplace_path,
      stafftools: biztools_marketplace_listing_path(listing.slug),
      canonical_url: marketplace_listing_url(listing.slug),
      richweb: {
        title: "#{listing.name} - GitHub Marketplace",
        url: request&.original_url,
        description: listing.short_description,
        image: og_image
      },
      breadcrumb_owner: :marketplace,
      breadcrumb: listing.name
    }
  end

  sig { void }
  def dismiss_dashboard_copilot_extensions_docker_nudge
    return unless params[:utm_campaign] == "dashboard_copilot_extensions_docker_nudge" && current_user&.feature_enabled?(:dashboard_copilot_extensions_docker_nudge)
    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.dismiss_notice(:dashboard_copilot_extensions_docker)
    end
  end
end
