# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BillingController < Stafftools::Businesses::BusinessBaseController
  include Stafftools::BillingPermissionCheck
  include BillingSettingsHelper
  include Billing::ProductsDependency
  include Billing::CopilotLicenseSnapshot
  include Customers::Concerns::BillingPayload

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:emails]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:subscription_status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    has_metered_services_locked = this_business.metered_services_locked?

    render "stafftools/businesses/billing/show", locals: {
      business: this_business,
      has_metered_services_locked: has_metered_services_locked
    }
  end

  def update
    customer = this_business.customer || ::Billing::CreateCustomer.perform(this_business,
      actor: current_user).customer

    if customer.update(billing_customer_params)
      redirect_to stafftools_enterprise_billing_path(this_business)
    else
      flash[:error] = customer.errors.full_messages.to_sentence
      redirect_to :back
    end
  end

  def subscription_status # rubocop:todo GitHub/UseRestfulActions
    render Stafftools::Billing::Businesses::SubscriptionStatusComponent.new(business: this_business),
      layout: false
  end

  def emails # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/billing_emails", locals: { owner: this_business }
  end

  def run_pending_changes # rubocop:todo GitHub/UseRestfulActions
    plan_change =
      if params[:pending_change_id]
        this_business.pending_plan_changes.find_by(id: params[:pending_change_id])
      else
        this_business.pending_cycle_change
      end

    unless plan_change
      flash[:error] = "No pending plan change was found for #{this_business}"
      return redirect_to :back
    end

    if plan_change.run
      flash[:notice] = "Pending plan changes were successfully applied for #{this_business}."
    else
      flash[:error] = "Unable to run pending plan changes: #{plan_change.errors.full_messages.join(", ")}"
    end

    redirect_to :back
  end

  # Skip billing checks for :packages and :storage for an year
  # Adds a comment in the github/gitcoin/issues/4042 issue for tracking
  def stop_billing_check # rubocop:todo GitHub/UseRestfulActions
    stop_billing_check_helper(this_business, T.must(current_user))
  end

  def sync_customer # rubocop:todo GitHub/UseRestfulActions
    customer = this_business.customer || ::Billing::CreateCustomer.perform(this_business, actor: current_user).customer
    ::Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
    flash[:notice] = "Customer information successfully synced with billing platform for #{this_business}."
    redirect_to :back
  end

  def refresh_pooled_entitlement # rubocop:todo GitHub/UseRestfulActions
    customer_id = this_business.customer_id

    unless customer_id
      flash[:error] = "No customer ID found for #{this_business}."
      return redirect_to :back
    end

    response = refresh_copilot_license_snapshot(owner: this_business, customer_id: customer_id)

    if response.error?
      flash[:error] = "Failed to refresh pooled entitlement for #{this_business}: #{response.error_message}"
    else
      flash[:notice] = "Pooled entitlement refreshed for #{this_business} " \
        "(CFB seats: #{response.copilot_for_business_count}, CE seats: #{response.copilot_enterprise_count})."
    end

    redirect_to :back
  end

  def reset_pooled_entitlement # rubocop:todo GitHub/UseRestfulActions
    customer_id = this_business.customer_id

    unless customer_id
      flash[:error] = "No customer ID found for #{this_business}."
      return redirect_to :back
    end

    current_amount = params[:current_amount]

    unless current_amount.present?
      flash[:error] = "Current amount is required."
      return redirect_to :back
    end

    parsed_amount = Float(current_amount)
    if !parsed_amount.finite? || parsed_amount.negative?
      flash[:error] = "Current amount must be a non-negative finite number."
      return redirect_to :back
    end

    response = ::Billing::Platform::Api::Client.new.admin_reset_pooled_entitlement_current_amount(
      customer_id: customer_id,
      current_amount: parsed_amount,
    )

    if response.is_a?(Billing::Platform::Api::Error)
      flash[:error] = "Failed to reset pooled entitlement for #{this_business}: #{response.message}"
    elsif response.is_a?(Hash) && response[:success] == false
      flash[:error] = "Failed to reset pooled entitlement for #{this_business}."
    else
      flash[:notice] = "Pooled entitlement current amount reset to $#{"%.2f" % parsed_amount} for #{this_business}."
    end

    redirect_to :back
  rescue ArgumentError
    flash[:error] = "Current amount is not a valid number."
    redirect_to :back
  end

  private

  def billing_customer_params
    params.require(:customer).permit(
      :azure_subscription_id,
      :metered_ghe,
      :metered_via_azure
    )
  end

  def usage_filter_params
    params.except(:slug).permit(:customer_id, :period, :product, :sku, :query, :group, :page, :chart_type, :unit_type).to_h.symbolize_keys
  end

  def customer_id
    this_business.customer_id
  end
end
