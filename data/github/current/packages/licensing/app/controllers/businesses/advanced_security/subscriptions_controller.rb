# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::SubscriptionsController < ::Businesses::AdvancedSecurity::SelfServeController
  include BillingSettingsHelper
  include VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    if !this_business.has_active_advanced_security_subscription?
      return respond_with_error("This account is not subscribed to Advanced Security")
    end

    this_business.cancel_advanced_security_subscription(actor: current_user)
    analytics_event(
      category: "business_advanced_security_subscription",
      action: "cancel_subscription",
      label: "business_id:#{this_business.id}",
    )
    respond_with_success("Your Advanced Security subscription has been successfully scheduled for cancellation.", {
      newPendingCycleChange: ghas_pending_plan_change_payload(this_business),
    })
  end
end
