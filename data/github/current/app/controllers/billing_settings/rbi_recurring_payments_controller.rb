# typed: strict
# frozen_string_literal: true

class BillingSettings::RBIRecurringPaymentsController < ApplicationController
  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_eligible

  # Hardcoded list of user IDs approved for RBI recurring payments opt-in.
  # These are trusted India RBI customers identified by Platform Health.
  ELIGIBLE_USER_IDS = T.let(
    [
      5379650,
      13602136,
      16759453,
      1096565,
      5147164,
      8438278,
      16719467,
      17374859,
      83968938,
    ].freeze,
    T::Array[Integer],
  )

  sig { void }
  def create
    user = current_user

    # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage -- self-service opt-in for trusted RBI customers
    FeatureFlag.vexi_management.add_feature_flag_actors(
      :billing_india_rbi_recurring_payments,
      [user],
    )
    # rubocop:enable GitHub/FeatureManagement/NoVexiManagementUsage

    flash[:notice] = "Recurring payments enabled. Please update your payment method below to complete setup."
    redirect_to settings_user_billing_tab_path(tab: "payment_information")
  end

  private

  sig { returns(T.untyped) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  sig { void }
  def ensure_eligible
    unless ELIGIBLE_USER_IDS.include?(current_user.id)
      render_404
    end
  end
end
