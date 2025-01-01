# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::SubscriptionsController < ::Businesses::AdvancedSecurity::SelfServeController
  extend T::Sig
  include BillingSettingsHelper

  sig { void }
  def update
    if !this_business.has_active_advanced_security_subscription?
      flash[:business_committers_error] = "This account is not subscribed to Advanced Security"
      return redirect_to_billing_settings_or_return_to
    end

    this_business.cancel_advanced_security_subscription(actor: current_user)
    flash[:business_committers_success] = "Your Advanced Security subscription has been successfully scheduled for cancellation."
    analytics_event(
      category: "business_advanced_security_subscription",
      action: "cancel_subscription",
      label: "business_id:#{this_business.id}",
    )
    redirect_to_billing_settings_or_return_to
  end
end
