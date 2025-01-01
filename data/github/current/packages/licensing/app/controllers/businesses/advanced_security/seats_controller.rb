# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::SeatsController < ::Businesses::AdvancedSecurity::SelfServeController
  include BillingSettingsHelper
  include VerifiedFetchDependency

  before_action only: [:update] do
    T.bind(self, Businesses::AdvancedSecurity::SeatsController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information))
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
  only: [:show]

  allow_verified_fetch only: [:show, :update]

  EMDASH = "\u{2014}"

  sig { void }
  def show
    return render_404 unless request.xhr?
    old_seats = this_business.advanced_security_seats_for_entity
    new_seats = params[:seats].to_i || advanced_security_seats
    new_seats = [[new_seats.to_i, minimum_seat_count].max, maximum_seat_count].min
    new_price = this_business.advanced_security_price(seats: new_seats)
    old_price = this_business.advanced_security_price(seats: old_seats)

    difference = (new_price - old_price).abs.format

    next_payment = this_business.advanced_security_subscription_item&.next_billing_date&.strftime("%B %-e, %Y")

    payment_due_notice = "Your next payment of #{new_price} will be due on #{next_payment}"
    if new_seats < old_seats
      payment_due_notice = "Your changes will take effect on #{next_payment}"
    elsif new_seats == old_seats
      payment_due_notice = " "
    end

    sales_tax_notice = " "
    if this_business.display_sales_tax_on_checkout? && new_seats > old_seats
      sales_tax_notice = "Sales tax will be added to your invoice"
    end

    render json: {
      total_seats: new_seats,
      old_seats: old_seats,
      current_price: new_price.format,
      payment_increase: new_seats > old_seats ? difference : nil,
      payment_decrease: new_seats < old_seats ? difference : nil,
      payment_due: new_seats <= old_seats ? EMDASH : difference,
      payment_due_notice: payment_due_notice,
      sales_tax_notice: sales_tax_notice,
    }
  end

  sig { void }
  def update
    return respond_with_error("This account is not enrolled in advanced security") unless eligible_for_self_serve_ghas?

    old_seats = this_business.advanced_security_seats_for_entity
    new_seats = params[:seats].to_i
    return respond_with_error("Number of committers must be greater than 0.") if new_seats <= 0

    seat_delta = new_seats - old_seats
    max_seat_delta = ::Billing::ChangeSubscription::MAX_SEAT_DELTA
    return respond_with_error("You can only add or remove up to #{max_seat_delta} committers at a time.") if seat_delta.abs > max_seat_delta

    active_committers = this_business.advanced_security_license.consumed_seats
    return respond_with_error("Number of committers must be greater than current active committers.") if new_seats < active_committers

    max_allowed_seats = Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_MAX_NUMBER_OF_SEATS
    return respond_with_error("Number of committers must be fewer than #{max_allowed_seats}.") if new_seats > max_allowed_seats

    begin
      this_business.set_advanced_security_seats_for_entity(seats: new_seats, actor: current_user)
      success_message = if new_seats > old_seats
        "Number of GitHub Advanced Security #{"Committer".pluralize(new_seats)} updated to #{new_seats}."
      else
        "Downgrade to #{new_seats} GitHub Advanced Security #{"Committer".pluralize(new_seats)} scheduled."
      end
      update_seats_analytics_event(
        new_seats > old_seats ? "upgrade_self_serve_seats" : "downgrade_self_serve_seats",
        old_seats,
        new_seats,
      )
      respond_with_success(success_message, {
        success: success_message,
        newPayment: this_business.advanced_security_price(seats: new_seats).format,
        newSeatCount: new_seats,
        newPendingCycleChange: ghas_pending_plan_change_payload(this_business),
      })
    rescue Configurable::AdvancedSecurityBillingConfig::SubscriptionNotFoundError
      respond_with_error("Failed to update number of GitHub Advanced Security Committers: subscription doesn't exist.")
    rescue Configurable::AdvancedSecurityBillingConfig::SubscriptionQuantityCannotBeZero
      respond_with_error("Failed to update number of GitHub Advanced Security Committers: can't set committers to 0.")
    rescue Configurable::AdvancedSecurityBillingConfig::Error
      respond_with_error("Failed to update number of GitHub Advanced Security Committers")
    end
  end

  private

  sig { returns(Integer) }
  memoize def advanced_security_seats
    this_business.advanced_security_seats_for_entity
  end

  sig { returns(Integer) }
  memoize def active_advanced_security_seats
    this_business.advanced_security_license.consumed_seats
  end

  sig { returns(Integer) }
  memoize def minimum_seat_count
    [1, active_advanced_security_seats, advanced_security_seats - ::Billing::ChangeSubscription::MAX_SEAT_DELTA].max
  end

  sig { returns(Integer) }
  memoize def maximum_seat_count
    advanced_security_seats + ::Billing::ChangeSubscription::MAX_SEAT_DELTA
  end

  sig { returns(T::Boolean) }
  def eligible_for_self_serve_ghas?
    return false if GitHub.enterprise?
    return false if this_business.enterprise_managed_user_enabled?
    this_business.advanced_security_purchased_for_entity?
  end

  sig { params(action: String, old_seats: Integer, new_seats: Integer).void }
  def update_seats_analytics_event(action, old_seats, new_seats)
    analytics_event(
      category: "business_advanced_security_subscription",
      action: action,
      label: "business_id:#{this_business.id},old_seats:#{old_seats},new_seats:#{new_seats}"
    )
  end
end
