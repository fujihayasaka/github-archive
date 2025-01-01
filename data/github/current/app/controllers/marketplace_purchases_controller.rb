# typed: true
# frozen_string_literal: true

class MarketplacePurchasesController < ApplicationController
  include TradeControlsControllerMethods

  before_action :marketplace_required
  before_action :login_required, except: :preview
  before_action :require_xhr, only: :preview
  before_action only: [:create, :update] do
    T.bind(self, MarketplacePurchasesController)
    check_trade_compliance(target: target, sdn_redirect: true)
  end
  before_action :sign_end_user_agreement, only: [:create, :update]
  before_action only: :new do
    T.bind(self, MarketplacePurchasesController)
    check_trade_compliance(target: target)
  end
  before_action :this_marketplace_listing_required, only: [:new, :preview, :integrator_upgrade]

  layout "layouts/marketplace"
  javascript_bundle :billing, only: [:new, :preview, :integrator_upgrade]
  stylesheet_bundle :marketplace

  before_action :add_csp_exceptions, only: :new
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:integrator_upgrade]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:preview]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :integrator_upgrade], optional: true

  # For editing billing information within a modal
  CSP_EXCEPTIONS = {
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
    frame_src: [GitHub.zuora_payment_page_server].freeze,
  }.freeze

  DEFAULT_UNIT_QUANTITY = 1
  MAX_UNIT_QUANTITY     = 100_000

  def delete_pending # rubocop:todo GitHub/UseRestfulActions
    preview = Marketplace::OrderPreview.where(user: current_user).find(params[:id])
    listing_plan = Marketplace::ListingPlan.find_by(id: preview.marketplace_listing_plan_id)
    listing_plan_name = listing_plan&.name
    pending_order_name = preview.listing&.name


    GitHub.dogstats.increment("marketplace.order_previews.deleted", tags: ["notified:#{preview.notification_sent?}"])
    GlobalInstrumenter.instrument("marketplace.order_preview_deleted", {
      user: current_user,
      order_preview_viewed_at: preview.viewed_at,
      order_preview_email_notification_sent_at: preview.email_notification_sent_at,
      account: preview.account,
      marketplace_listing_id: preview.marketplace_listing_id,
      marketplace_listing_plan_id: preview.marketplace_listing_plan_id,
    })

    preview.destroy
    flash[:notice] = "#{pending_order_name}'s #{listing_plan_name} plan has been deleted."

    redirect_to marketplace_pending_orders_path
  end

  def new
    selected_plan = this_marketplace_listing_plan
    return render_404 if selected_plan.nil?
    return render_404 if current_user.is_emu_org_owner? && !current_user.is_emu_admin? && selected_plan.paid?
    return render_404 unless selected_plan.present? && selected_plan.listing.slug == params[:listing_slug]

    selected_plan_quantity = unit_quantity(selected_plan)

    set_setup_state_cookie(this_marketplace_listing) unless pjax?

    payment_account = user_or_business_payment_account
    subscription = payment_account.get_plan_subscription_or_null_plan
    subscription_item = if payment_account.business? && payment_account.self_serve_payment?
      payment_account.subscription_item_for_marketplace_listing(this_marketplace_listing, organization: installation_account)
    else
      payment_account.subscription_item_for_marketplace_listing(this_marketplace_listing)
    end
    quantity = selected_plan.per_unit == true ? (subscription_item&.quantity || selected_plan_quantity) : selected_plan_quantity

    if this_marketplace_listing.archived?
      if current_user_can_admin_listing?(this_marketplace_listing)
        return redirect_to_listing_with_delisted_error(this_marketplace_listing)
      end

      return redirect_to_billing_settings_with_delisted_error(
        marketplace_listing: this_marketplace_listing,
        subscription_item: subscription_item,
      )
    end

    # User is trying to modify an org's subscription they don't have permission for:
    if subscription_item.present? && !subscription_item.adminable_by?(current_user)
      return redirect_to_listing_with_permission_error(this_marketplace_listing)
    end

    # User is trying to purchase on behalf of an org for which they don't have permission:
    unless viewer_can_purchase_on_behalf_of_account?(payment_account)
      return redirect_to_listing_with_permission_error(this_marketplace_listing)
    end

    # Update the order preview/cart data in the background
    UpdateMarketplaceOrderPreviewJob.perform_later(current_user.id, this_marketplace_listing.id, installation_account.id, selected_plan.id, quantity, Time.now.to_i)

    order_preview_view = create_view_model(
      MarketplacePurchases::OrderPreviewView,
      listing: this_marketplace_listing,
      selected_plan: selected_plan,
      selected_plan_quantity: selected_plan_quantity,
      quantity: quantity,
      return_to: request.url,
      account: payment_account,
      installation_account: installation_account,
    )

    strip_analytics_query_string
    instrument_billing_form_loaded(flow: "MARKETPLACE_PURCHASE")

    render "marketplace_purchases/new", locals: {
      selected_plan: selected_plan,
      account: payment_account,
      organization: organization,
      subscription: subscription,
      subscription_item: subscription_item,
      order_preview_view: order_preview_view,
      quantity: quantity,
      agreement: Marketplace::Agreement.latest_for_end_users,
      listing: this_marketplace_listing,
      is_emu_org_admin: current_user.is_emu_org_owner?
    }
  end

  def integrator_upgrade # rubocop:todo GitHub/UseRestfulActions
    plan = this_marketplace_listing.listing_plans.find_by_number!(params[:plan_number])
    return render_404 unless plan.can_user_see?(current_user)

    redirect_params = {
      listing_slug: this_marketplace_listing.slug,
      plan_id: plan.global_relay_id,
    }
    account_login = selected_account.display_login if selected_account_valid?
    redirect_params[:account] = account_login unless account_login == current_user.display_login

    redirect_to marketplace_order_path(redirect_params)
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    return head :unauthorized unless logged_in?

    selected_plan = this_marketplace_listing_plan

    return render_404 unless selected_plan

    quantity = unit_quantity(selected_plan)
    payment_account = user_or_business_payment_account

    # User is trying to purchase on behalf of an org for which they don't have permission:
    return render_404 unless viewer_can_purchase_on_behalf_of_account?(payment_account)

    # Update the order preview/cart data in the background
    UpdateMarketplaceOrderPreviewJob.perform_later(current_user.id, this_marketplace_listing.id, installation_account.id, selected_plan.id, quantity, Time.now.to_i)

    respond_to do |format|
      format.html do
        render partial: "marketplace_purchases/order_preview", locals: {
          view: create_view_model(MarketplacePurchases::OrderPreviewView, {
            listing: this_marketplace_listing,
            selected_plan: selected_plan,
            selected_plan_quantity: quantity,
            quantity: quantity,
            account: payment_account,
            installation_account: installation_account,
          }),
          agreement: Marketplace::Agreement.latest_for_end_users,
          listing: this_marketplace_listing,
          account: payment_account,
          organization: organization,
        }
      end
    end
  end

  def create
    return render_404 unless logged_in? && this_marketplace_listing_plan.present?

    begin
      subscription_item = Billing::CreateMarketplaceSubscriptionItem.call(
        listing_plan: this_marketplace_listing_plan,
        quantity: params[:quantity].to_i,
        account: selected_account,
        installation_account: selected_installation_account,
        grant_oap: params[:grant_oap].present?,
        viewer: current_user,
      )[:subscription_item]
    rescue Platform::Errors::Execution, Billing::CreateSubscriptionItem::ForbiddenError, Billing::CreateSubscriptionItem::UnprocessableError => e
      flash[:error] = e.message
      return redirect_to :back
    end

    listing_plan = subscription_item.subscribable
    listing = listing_plan.listing

    session[:last_click_marketplace_listing_id] = listing.id
    redirect_url = install_marketplace_listing_path(listing.slug, subscription_item.global_relay_id)

    GlobalInstrumenter.instrument(Marketplace::Events::LISTING_INSTALL, {
      user: current_user,
      listing_id: listing.id,
      listing_plan_id: listing_plan.id,
      quantity: subscription_item.quantity,
    })
    instrument_billing_form_submitted(flow: "MARKETPLACE_PURCHASE")

    redirect_to redirect_url
  end

  def update
    return render_404 unless logged_in? && this_marketplace_listing_plan.present?

    account = selected_account || current_user
    plan_subscription = account.plan_subscription

    begin
      subscription_item = Billing::UpdateSubscriptionItem.call(
        subscribable: this_marketplace_listing_plan,
        quantity: params[:quantity].to_i,
        grant_oap: params[:grant_oap].present?,
        viewer: current_user,
        plan_subscription: plan_subscription,
        installation_account: selected_installation_account,
      ).subscription_item
    rescue Billing::UpdateSubscriptionItem::ForbiddenError, Platform::Errors::NotFound, Platform::Errors::Forbidden, Platform::Errors::ServiceUnavailable
      return render_404
    rescue Platform::Errors::Execution, Billing::UpdateSubscriptionItem::UnprocessableError => e
      flash[:error] = e.message
      return redirect_to :back
    end

    # Make sure the app is installed for the account
    if current_user.feature_enabled?(:marketplace_purchase_reconciliation) && !this_marketplace_listing.installed_for?(target)
      session[:last_click_marketplace_listing_id] = this_marketplace_listing.id
      redirect_url = install_marketplace_listing_path(this_marketplace_listing.slug, subscription_item.global_relay_id)

      GlobalInstrumenter.instrument(Marketplace::Events::LISTING_INSTALL, {
        user: current_user,
        listing_id: this_marketplace_listing.id,
        listing_plan_id: this_marketplace_listing.id,
        quantity: subscription_item.quantity,
      })
      instrument_billing_form_submitted(flow: "MARKETPLACE_PURCHASE")

      redirect_to redirect_url
      return
    end

    if selected_account.business?
      redirect_to settings_billing_enterprise_url(selected_account)
    elsif current_user.display_login == selected_account&.display_login || selected_account.nil?
      redirect_to settings_user_billing_url.to_s
    else
      redirect_to settings_org_billing_url(selected_account)
    end
  end

  private

  memoize def selected_account
    if params[:account]
      params[:installation_account].present? ? Business.find_by(slug: params[:account]) : User.find_by_login(params[:account])
    elsif params[:account_id]
      User.find_by(id: params[:account_id])
    end
  end

  memoize def selected_installation_account
    return if !selected_account&.business?
    return if params[:installation_account].nil?

    selected_account.organizations.find_by_login(params[:installation_account])
  end

  def selected_account_valid?
    selected_account.present? &&
      (selected_account.user? || selected_account.organization?) &&
      !selected_account.hide_from_user?(current_user)
  end

  def target_for_conditional_access
    # This is OK as we have a before_action :login_required
    target || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def target
    selected_installation_account.presence || selected_account.presence || current_user
  end

  def sign_end_user_agreement
    return if params[:marketplace_agreement_id].blank?

    listing = Marketplace::Listing.find(params[:marketplace_listing_id])
    agreement = Marketplace::Agreement.find(params[:marketplace_agreement_id])

    if agreement.integrator?
      if listing.can_sign_integrator_agreement?(current_user, agreement: agreement)
        unless listing.sign_agreement(current_user, agreement: agreement)
          error_message = "Could not sign the GitHub #{agreement.name}."
        end
      else
        error_message = "You do not have permission to sign the GitHub #{agreement.name} for the specified listing."
      end
    elsif agreement.end_user?
      if listing.can_sign_end_user_agreement?(current_user, agreement: agreement)
        unless listing.sign_agreement(current_user, agreement: agreement)
          error_message = "Could not sign the GitHub #{agreement.name}."
        end
      else
        error_message = "You do not have permission to sign the GitHub #{agreement.name} for the specified listing."
      end
    end

    if error_message.present?
      flash[:error] = error_message
      redirect_to marketplace_listing_path(params[:listing_slug])
    end
  end

  def current_user_can_admin_listing?(marketplace_listing)
    logged_in? && (marketplace_listing.adminable_by?(current_user) ||
      current_user.can_admin_marketplace_listings?)
  end

  def unit_quantity(selected_plan)
    quantity = [params[:quantity].to_i.abs, MAX_UNIT_QUANTITY].min

    if selected_plan.per_unit && quantity > 0
      quantity
    else
      DEFAULT_UNIT_QUANTITY
    end
  end

  def set_setup_state_cookie(marketplace_listing)
    if params[:state] && marketplace_listing.listable_is_integration?
      IntegrationInstallation::SetupStateCookie.create(
        cookie_jar: cookies,
        data: { state: params[:state] },
        integration_id: marketplace_listing.listable.global_relay_id,
        target_id: params[:suggested_target_id],
      )
    end
  end

  def redirect_to_listing_with_permission_error(marketplace_listing)
    flash[:error] = "You do not have permission to set up plans for the specified account."
    redirect_to marketplace_listing_path(marketplace_listing.slug)
  end

  def redirect_to_listing_with_delisted_error(marketplace_listing)
    flash[:error] = "#{marketplace_listing.name} has been removed from GitHub Marketplace."
    redirect_to marketplace_listing_path(marketplace_listing.slug)
  end

  def redirect_to_billing_settings_with_delisted_error(marketplace_listing:, subscription_item:)
    if subscription_item.present?
      flash[:error] = "#{marketplace_listing.name} has been removed from GitHub Marketplace. You can cancel your subscription below."
    else
      flash[:error] = "#{marketplace_listing.name} has been removed from GitHub Marketplace. You can cancel your subscription by navigating to your organization's billing settings."
    end

    redirect_to settings_user_billing_path
  end

  # Ensures the given user/org matches the 'account' URL parameter, if any such URL parameter
  # was set.
  def viewer_can_purchase_on_behalf_of_account?(account)
    return true if params[:account].blank?

    if account.business?
      account.organizations.pluck(:display_login).include?(params[:account])
    else
      account.display_login.downcase == params[:account].to_s.downcase
    end
  end

  def user_or_business_payment_account
    if installation_account&.organization? \
      && installation_account&.business&.self_serve_payment?
      installation_account.business
    else
      installation_account
    end
  end

  memoize def organization
    org = selected_account&.business? ? selected_installation_account : selected_account
    org_login = org&.display_login || ""
    current_user.owned_organizations.where(login: org_login).first
  end

  memoize def installation_account
    organization || current_user
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing&.can_viewer_see?(current_user)
  end

  memoize def this_marketplace_listing_plan
    typed_object_from_id([Platform::Objects::MarketplaceListingPlan], params[:plan_id])
  rescue Platform::Errors::NotFound
    nil
  end
end
