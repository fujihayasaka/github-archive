# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BillingController < Stafftools::Businesses::BusinessBaseController
  include Stafftools::BillingPermissionCheck
  include BillingSettingsHelper

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

  private

  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  def billing_customer_params
    params.require(:customer).permit(
      :azure_subscription_id,
      :metered_ghe,
      :metered_via_azure
    )
  end

  def usage_filter_params
    params.except(:slug).permit(:customer_id, :period, :product, :query, :group, :page).to_h.symbolize_keys
  end

  def ensure_vnext_enabled
    render_404 unless this_business.customer&.billed_via_billing_platform?
  end

  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  def enabled_products
    enabled_products = this_business.customer.products_billed_via_billing_platform
    # enabled_products is an array of strings, so we need to get all products from bp since we need friendly names for the UI
    all_products.select { |product| enabled_products.include?(product[:name]) }
  end

  def customer_id
    this_business.customer_id
  end
end
