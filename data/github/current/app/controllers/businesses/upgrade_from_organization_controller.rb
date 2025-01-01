# typed: true
# frozen_string_literal: true

class Businesses::UpgradeFromOrganizationController < Businesses::BusinessController
  include BillingSettingsHelper

  before_action :organization_upgrade_initiated_required
  before_action :upgrade_initiated_by_another_user, only: [:new]
  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :eligible_for_self_serve_payment_required
  before_action :add_csp_exceptions, only: [:new]
  before_action only: [:new] do
    T.bind(self, Businesses::UpgradeFromOrganizationController)
    check_trade_compliance(target: this_business, feature_type: :direct_org_to_enterprise_upgrade)
  end

  before_action only: [:create] do
    T.bind(self, Businesses::UpgradeFromOrganizationController)
    check_trade_compliance(target: this_business, feature_type: :direct_org_to_enterprise_upgrade, sdn_redirect: true)
  end

  skip_before_action :redirect_if_organization_upgrade_initiated

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Configurations,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Billing,
  ApplicationRecord::Repositories,
  only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:new], optional: true

  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  javascript_bundle :"billing-settings"
  javascript_bundle :billing, only: [:new]

  stylesheet_bundle :settings

  def new
    return render_404 unless this_business.self_serve_payment?
    return render_404 unless this_business.upgrade_initiated_from_organization.present?
    upgrading_organization = this_business.upgrade_initiated_from_organization

    selected_duration = params[:plan_duration] || default_plan_duration(this_business)
    respond_to do |format|
      format.html do
        render "businesses/billing_settings/purchase_org_upgrade_to_enterprise", locals: {
          this_business: this_business,
          upgrading_organization: upgrading_organization,
          selected_duration: selected_duration
        }
      end
      format.json do
        duration_in_months = selected_duration == User::BillingDependency::MONTHLY_PLAN ? 1 : 12
        seats = params[:seats] ? params[:seats].to_i : this_business.seats
        seats = [seats, this_business.seat_limit_for_upgrades].min
        seats = [seats, upgrading_organization.default_seats, 1].max
        plan = GitHub::Plan.business_plus(account: this_business)
        subscription = Billing::Subscription.for_account(
          this_business,
          seats: seats,
          plan: plan,
          duration_in_months: duration_in_months
        )
        plan_change = Billing::PlanChange::PerSeatPricingModel.new(
          this_business,
          plan_duration: selected_duration,
          new_plan: plan,
          seats: seats,
          plan_effective_at: nil
        )
        render json: {
          seats: seats,
          duration: selected_duration,
          selectors: {
            ".unstyled-renewal-price" => subscription.undiscounted_price.format,
            ".unstyled-payment-due" => plan_change.renewal_price(github_only: plan_change.changing_duration?).format,
            ".unstyled-new-seats" => seats,
          },
        }
      end
    end
  end

  def create
    return render_404 unless this_business.upgrade_initiated_from_organization.present?
    upgrading_organization = this_business.upgrade_initiated_from_organization

    new_seats = params[:seats]&.to_i || upgrading_organization.default_seats
    if new_seats < upgrading_organization.default_seats
      flash[:error] = "The number of seats in your organization has changed and we cannot complete your upgrade. In order to proceed, confirm the number of seats you require and try again."
      return redirect_to billing_upgrade_from_organization_enterprise_path(this_business)
    elsif !this_business.has_valid_payment_method? || !this_business.has_saved_trade_screening_record_with_information?
      flash[:error] = "You must add billing information and a valid payment method to complete your GitHub Enterprise purchase."
      return redirect_to billing_upgrade_from_organization_enterprise_path(this_business)
    end

    this_business.seats = new_seats
    this_business.plan_duration = params[:plan_duration] unless params[:plan_duration].blank?
    this_business.save

    if this_business.upgrade_from_free_or_business_plan_org(current_user)
      analytics_event(
        category: "enterprise_account",
        action: "complete_organization_upgrade_to_enterprise_account",
        label: "enterprise_id:#{this_business.id};seats:#{this_business.seats};duration:#{this_business.plan_duration}"
      )
      redirect_to enterprise_path(this_business)
    else
      # Get out of the purchase state if required, and redirect back to the checkout page
      this_business.initiate_organization_upgrade(current_user) if this_business.organization_upgrade_purchase_initiated?
      flash[:error] = "Failed to complete GitHub Enterprise purchase. Please try again later or contact support."
      redirect_to billing_upgrade_from_organization_enterprise_path(this_business)
    end
  end

  def destroy
    upgrading_organization = this_business.upgrade_initiated_from_organization

    if this_business.cancel_organization_upgrade(current_user)
      flash[:notice] = "Your GitHub Enterprise purchase has been cancelled."
      redirect_to upgrading_organization.present? ? settings_org_billing_path(upgrading_organization) : "/"
    else
      flash[:error] = "Failed to cancel GitHub Enterprise purchase. Please try again later or contact support."
      redirect_to billing_upgrade_from_organization_enterprise_path(this_business)
    end
  end

  private

  def upgrade_initiated_by_another_user
    return if this_business.adminable_by?(current_user)
    return render_404 unless this_business.upgrade_initiated_from_organization.adminable_by?(current_user)

    abandon_date = (this_business.created_at + 5.days).to_date.to_formatted_s(:long_ordinal)
    flash[:warn] = "An upgrade has already been initiated by #{this_business.admins.first.name}, please reach out to " \
      "them to finish the process. This process will be considered abandoned if not completed by #{abandon_date}; " \
      "at which point you'll be able to try again."
    redirect_to :back
  end
end
