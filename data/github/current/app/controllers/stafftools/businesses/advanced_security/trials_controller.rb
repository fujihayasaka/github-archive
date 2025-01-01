# typed: strict
# frozen_string_literal: true
class Stafftools::Businesses::AdvancedSecurity::TrialsController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig

  sig { void }
  def update
    operation_id = params[:operation_id]
    case operation_id
    when "expire_trial"
      result = this_business.end_advanced_security_trial_without_purchasing_now(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        is_stafftools_action: true,
      )
      if result.ok?
        flash[:notice] = "Expired Advanced Security Trial."
      else
        flash[:error] = "Failed to expire Advanced Security Trial: #{result.error.message}"
      end
      redirect_to stafftools_enterprise_path(this_business)
    when "extend_trial"
      result = this_business.extend_advanced_security_trial(
        actor: current_user,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        days: 7,
        is_stafftools_action: true,
      )
      if result.ok?
        end_trial_date = result.value!.ends_on.strftime("%b %d, %Y")
        flash[:notice] = "Extended the Advanced Security trial. Trial will end on #{end_trial_date}."
      else
        flash[:error] = "Failed to extend Advanced Security Trial: #{result.error.message}"
      end
      redirect_to stafftools_enterprise_path(this_business)
    else
      render_404
    end
  end
end
