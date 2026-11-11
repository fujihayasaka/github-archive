# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::CustomersController < StafftoolsController
  before_action :sponsors_required
  before_action :ensure_sponsors_specific_plan_subscription_is_cancelled, only: :create
  before_action :ensure_sponsors_specific_customer_does_not_exist_or_inactive, only: :create
  before_action :require_sponsor, only: :create

  def create
    zuora_account_id = params[:zuora_account_id]
    result = Billing::CreateCustomer.perform(sponsor, actor: current_user, details: {
      omit_billing_info: true,
      zuora_account_id: zuora_account_id,
    }, purpose: :sponsors)

    if result.success?
      customer = result.customer
      flash[:notice] = if zuora_account_id.present?
        "Linked Zuora account #{zuora_account_id} as sponsorship-specific account for #{sponsor}"
      else
        "Created sponsorship-specific Zuora account #{customer.zuora_account_id} for #{sponsor}"
      end
    else
      flash[:error] = "Could not create a sponsorship-specific Zuora account for #{sponsor}: #{result.error_message}"
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  def destroy
    sponsors_customer = sponsor.sponsors_customer
    unless sponsors_customer
      flash[:notice] = "#{sponsor} does not have a sponsorship-specific Zuora account."
      return redirect_to(billing_stafftools_user_path(sponsor))
    end

    if sponsors_customer.active_subscription_items.any?
      flash[:error] = "Cannot delete #{sponsor}'s sponsorship-specific Zuora account because it has " \
        "active subscription item(s)."
    elsif sponsors_customer.destroy
      flash[:notice] = "Successfully unlinked #{sponsor}'s sponsorship-specific Zuora account. Sponsorships " \
        "will no longer be paid for by Zuora account #{sponsors_customer.zuora_account_id}."
    else
      errors = sponsors_customer.errors.full_messages.to_sentence
      flash[:error] = "Could not unlink #{sponsor}'s sponsorship-specific Zuora account: #{errors}"
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  memoize def sponsor
    User.find_by(login: params[:invoiced_sponsor_id])
  end

  def ensure_sponsors_specific_customer_does_not_exist_or_inactive
    sponsors_customer = sponsor.sponsors_customer
    return if sponsors_customer.nil? || !sponsors_customer.zuora_account_active?

    flash[:error] = "@#{sponsor} already has an active sponsorship-specific account for Zuora account ID " \
      "#{sponsors_customer.zuora_account_id}."
    redirect_to billing_stafftools_user_path(sponsor)
  end

  def require_sponsor
    render_404 unless sponsor
  end

  def ensure_sponsors_specific_plan_subscription_is_cancelled
    return unless sponsor.sponsors_plan_subscription # fine if they don't yet have a Sponsors-specific subscription

    # If they do have a Sponsors-specific subscription though, it needs to not be active on Zuora. We want the next
    # sponsorship they make after the Sponsors-specific customer is created to cause a new active Sponsors-specific
    # subscription to be created that's tied to that new customer, so that payment for their sponsorships comes
    # from the new customer's credit balance.
    unless sponsor.sponsors_plan_subscription.cancelled_or_non_zuora?
      flash[:error] = "@#{sponsor.display_login} currently has an active Sponsors-specific subscription on Zuora. " \
        "Please cancel any active sponsorships they have first."
      redirect_to billing_stafftools_user_path(sponsor)
    end
  end
end
