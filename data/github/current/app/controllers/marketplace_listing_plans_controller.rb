# typed: true
# frozen_string_literal: true

class MarketplaceListingPlansController < ApplicationController
  before_action :marketplace_required
  before_action :render_404, unless: :logged_in?
  before_action :sudo_filter
  before_action :this_marketplace_listing_required, only: [:show, :index, :new, :publish]
  before_action :this_marketplace_listing_plan_required, only: [:show, :update, :destroy, :publish, :retire]
  before_action :this_marketplace_listing_plan_admin_required, only: :publish

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :show],
    optional: true

  def index
    return render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)

    plans = this_marketplace_listing.listing_plans.scoped.order("marketplace_listing_plans.yearly_price_in_cents").limit(100)

    respond_to do |format|
      format.html do
        render "marketplace_listing_plans/index", locals: {
          marketplace_listing: this_marketplace_listing,
          marketplace_listing_plans: plans
        }
      end
    end
  end

  def new
    return render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)

    respond_to do |format|
      format.html do
        render "marketplace_listing_plans/new", locals: {
          listing_slug: this_marketplace_listing.slug,
          marketplace_listing: this_marketplace_listing
        }
      end
    end
  end

  def show
    return render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)
    return render_404 unless this_marketplace_listing == this_marketplace_listing_plan.listing

    respond_to do |format|
      format.html do
        render "marketplace_listing_plans/show", locals: {
          marketplace_listing: this_marketplace_listing,
          marketplace_listing_plan: this_marketplace_listing_plan
        }
      end
    end
  end

  def create
    begin
      result = Marketplace::CreateMarketplaceListingPlan.call(computed_create_plan_params)
    rescue Marketplace::CreateMarketplaceListingPlan::ForbiddenError => e
      return render_404
    rescue Marketplace::CreateMarketplaceListingPlan::UnprocessableError => e
      flash[:error] = e.message
      return redirect_to new_marketplace_listing_plan_path(params[:listing_slug])
    end

    plan = result[:marketplace_listing_plan]

    redirect_to marketplace_listing_plan_path(params[:listing_slug], plan.global_relay_id)
  end

  def update
    begin
      result = Marketplace::UpdateMarketplaceListingPlan.call(computed_plan_params.merge(plan: this_marketplace_listing_plan))
    rescue Marketplace::UpdateMarketplaceListingPlan::ForbiddenError => e
      return render_404
    rescue Marketplace::UpdateMarketplaceListingPlan::UnprocessableError => e
      flash[:error] = e.message
      return redirect_to marketplace_listing_plan_path(params[:listing_slug],
                                                       this_marketplace_listing_plan.global_relay_id)
    end

    plan = result[:marketplace_listing_plan]
    bullet_ids = plan.bullets.pluck(:id)

    unless create_bullets && update_bullets(bullet_ids)
      flash[:error] = "Could not save all bullet points for your new plan."
    end

    redirect_to marketplace_listing_plan_path(params[:listing_slug], plan.global_relay_id)
  end

  def publish # rubocop:todo GitHub/UseRestfulActions
    if this_marketplace_listing_plan.draft? && this_marketplace_listing_plan.can_publish?
      this_marketplace_listing_plan.publish!
      flash[:notice] = "Your plan has been published."
    else
      flash[:error] = this_marketplace_listing_plan.unpublishable_reason
    end

    redirect_to marketplace_listing_plan_path(params[:listing_slug], this_marketplace_listing_plan.global_relay_id)
  end

  def retire # rubocop:todo GitHub/UseRestfulActions
    begin
      if this_marketplace_listing_plan.retired?
        flash[:error] = "Can't change the state of retired listing plans."
      else
        return render_404 unless this_marketplace_listing_plan.allowed_to_edit?(current_user)
        this_marketplace_listing_plan.retire!(actor: current_user)
        flash[:notice] = "Your plan has been retired."
      end
    rescue Marketplace::ListingPlan::RetirementNotAllowed => e
      flash[:error] = e.message
    end

    redirect_to marketplace_listing_plan_path(params[:listing_slug], this_marketplace_listing_plan.global_relay_id)
  end

  def destroy
    return render_404 unless this_marketplace_listing_plan.allowed_to_delete?(current_user)

    listing = this_marketplace_listing_plan.listing

    unless this_marketplace_listing_plan.destroy
      errors = this_marketplace_listing_plan.errors.full_messages.join(", ")
      flash[:error] = "Could not delete listing plan: #{errors}"
      return redirect_to(marketplace_listing_plan_path(params[:listing_slug]))
    end

    redirect_to marketplace_listing_plans_path(listing.slug)
  end

  private

  def plan_params
    params.require(:marketplace_listing_plan).permit %i[name description unitName]
  end

  def computed_plan_params
    plan_params.to_h.merge(
      price_model: Platform::Enums::MarketplaceListingPlanPriceModel.coerce_isolated_input(params[:price_model]),
      monthly_price_in_cents: params[:monthly_price_in_dollars].to_i * 100,
      yearly_price_in_cents: params[:yearly_price_in_dollars].to_i * 100,
      has_free_trial: params[:has_free_trial].present?,
      for_account_type: Platform::Enums::MarketplaceListingPlanSubscriberAccountTypes.coerce_isolated_input(params[:for_account_type]),
      viewer: current_user,
    ).transform_keys(&:underscore).symbolize_keys
  end

  def computed_create_plan_params
    computed_plan_params.merge(
      slug: params[:listing_slug],
      bullet_values: Array(params[:bullet_values]).select(&:present?)
    )
  end

  def create_bullets
    return false unless this_marketplace_listing_plan.allowed_to_edit?(current_user)
    values = Array(params[:bullet_values]).select(&:present?)
    return true if values.empty?

    this_marketplace_listing_plan.bullets.build(values.map { |v| { value: v } })
    this_marketplace_listing_plan.save
  end

  def update_bullets(bullet_ids)
    return false unless this_marketplace_listing_plan.allowed_to_edit?(current_user)
    values_by_id = bullet_ids.map { |id| [id, params["bullet_values_#{id}"]] }.to_h
    return true if values_by_id.empty?

    results = values_by_id.map do |id, value|
      next unless bullet = this_marketplace_listing_plan.bullets.find_by(id: id)
      if value.present?
        bullet.update(value: value)
      else
        bullet.destroy
      end
    end

    results.all?
  end

  memoize def selected_listing_owner
    this_marketplace_listing.owner if this_marketplace_listing.present?
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    return render_404 unless this_marketplace_listing
  end

  memoize def this_marketplace_listing_plan
    typed_object_from_id([Platform::Objects::MarketplaceListingPlan], params[:id])
  rescue Platform::Errors::NotFound
    nil
  end

  def this_marketplace_listing_plan_required
    return render_404 unless this_marketplace_listing_plan
  end

  def this_marketplace_listing_plan_admin_required
    return render_404 unless this_marketplace_listing_plan.adminable_by?(current_user)
  end

  def target_for_conditional_access
    case params[:action]
    when "index", "create", "show", "new"
      # listing ownership related targets
      selected_listing_owner
    when "update", "publish", "retire", "destroy"
      # for these actions listing plan owner is the target
      this_marketplace_listing_plan&.listing&.owner
    else
      # Whenever a new route is added to this controller it needs to be accounted for in this method
      raise Settings::EnterpriseInstallationsController::UnknownControllerActionExternalIdentyOrganization
    end
  end
end
