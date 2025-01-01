# typed: strict
# frozen_string_literal: true

class Stafftools::Users::BillingController < StafftoolsController
  include Stafftools::BillingPermissionCheck
  include Stafftools::TradeCompliance::SharedControllerMethods
  include Stafftools::Users::ControllerLayoutMethods
  include BillingSettingsHelper
  include MarketingMethods
  include ReactHelper

  layout :billing_layout

  before_action :ensure_user_exists, except: [:invoiced]
  before_action :ensure_billing_enabled, only: [:charge, :invoiced]
  before_action :ensure_org_not_user, only: [:emails]

  before_action only: [
    :charge,
    :remove_credit_card,
    :pay_by_invoice,
    :pay_by_credit_card,
    :change_plan,
    :unlock_billing,
  ] do
    T.bind(self, Stafftools::Users::BillingController)
    ensure_target_not_restricted(feature_type: :cost_management)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:emails]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:emails],
    optional: true

  HIGH_RISK_SUDO_ACTIONS = T.let([
    :lock_billing,
    :unlock_billing,
  ].freeze, T::Array[Symbol])

  sig { void }
  def index
    # Get marketplace items for this user/organization
    user_subscription = this_user.get_plan_subscription_or_null_plan
    marketplace_items = user_subscription.active_marketplace_listing_subscription_items
        .includes(subscribable: [listing: [:listing_plans]])

    # Include marketplace items for this organization that are billed through the business
    if this_user.business.present? && !this_user.business.invoiced? && this_user.is_organization_billed_through_business?
      business_subscription = this_user.business.get_plan_subscription_or_null_plan
      marketplace_items = marketplace_items.or(business_subscription.active_marketplace_listing_subscription_items.for_organization(this_user)
        .includes(subscribable: [listing: [:listing_plans]]))
    end
    marketplace_items = marketplace_items.paginate(page: current_page, per_page: 30)

    if this_user.plan.per_seat? || (this_user.plan.free? && this_user.organization?)
      seat_change = ::Billing::PlanChange::SeatChange.new(this_user, seats: this_user.seats)
    end
    plan_changes = this_user.transactions.reverse
    enterprise_cloud_trial = ::Billing::EnterpriseCloudTrial.new(this_user)
    owned_private_repo_count = this_user.owned_private_repositories.count
    client = if this_user.delegate_billing_to_business?
      ::Billing::Api::ClientWrapper.new(billable_owner: this_user.billable_owner, owner: this_user)
    else
      ::Billing::Api::ClientWrapper.new(billable_owner: this_user)
    end
    copilot_monthly_usage = client.copilot_monthly_usage if this_user.plan.copilot_for_biz_eligible? &&
      Copilot::Organization.new(this_user).copilot_for_business_enabled?

    render "stafftools/users/billing", locals: {
      marketplace_items: marketplace_items,
      user: this_user,
      in_business: this_user.business.present?,
      copilot_monthly_usage: copilot_monthly_usage,
      plan_changes: plan_changes,
      seat_change: seat_change,
      owned_private_repo_count: owned_private_repo_count,
      any_private_repos: owned_private_repo_count > 0,
      enterprise_cloud_trial: enterprise_cloud_trial,
      in_enterprise_trial: enterprise_cloud_trial.active?,
      sponsorships_tab: sponsorships_tab
    }
  end

  sig { void }
  def emails # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/billing_emails", locals: { owner: this_user }
  end

  sig { void }
  def billing_managers # rubocop:todo GitHub/UseRestfulActions
    billing_managers = this_user.billing_managers.paginate(page: current_page)
    render "stafftools/users/billing_managers", locals: { user: this_user, billing_managers: billing_managers }
  end

  # Charges the user's card
  sig { void }
  def charge # rubocop:todo GitHub/UseRestfulActions
    if !this_user.has_valid_payment_method?
      flash[:error] = "No valid billing information or payment method on file for this user."
    elsif !(this_user.billed_on.nil? || this_user.billed_on <= Date.today || this_user.billing_attempts > 0)
      flash[:error] = "User cannot be charged at this time."
    else
      result = this_user.recurring_charge
      if result.success?
        # Accounts transitioning to external subscriptions are charged asynchronously
        flash[:notice] = "Charge initiated – check Payment History for status."
        return redirect_to stafftools_user_billing_history_url(this_user)
      else
        flash[:error] = result.error_message
      end
    end
    redirect_to :back
  end

  sig { void }
  def remove_credit_card # rubocop:todo GitHub/UseRestfulActions
    if this_user.remove_all_payment_methods(current_user)
      flash[:notice] = "Successfully removed all payment methods."
    else
      flash[:error] = "One or more payment methods were not removed."
    end
    redirect_to :back
  end

  sig { void }
  def pay_by_invoice # rubocop:todo GitHub/UseRestfulActions
    current_user = T.must(self.current_user)
    old_type = this_user.billing_type
    billed_on = Date.parse(params[:new_term_end_date]) + 1.day if params[:new_term_end_date]
    this_user.billed_on = billed_on
    this_user.switch_billing_type_to_invoice(current_user)
    if params[:plan] && params[:plan] != this_user.plan.to_s
      GitHub::Billing.change_subscription(this_user, actor: current_user, plan: params[:plan])
    end
    # This instrument call sends data to the Audit Log.
    # There is a similar instrumentation in User#switch_billing_type_to_invoice
    # that logs to Hydro but it does not have access to the stafftools controller context.
    instrument("billing.change_billing_type",
               old_billing_type: old_type,
               billing_type: this_user.billing_type,
               user: this_user)
    flash[:notice] = "Successfully switched account to invoice billing."
    redirect_to :back
  end

  sig { void }
  def pay_by_credit_card # rubocop:todo GitHub/UseRestfulActions
    old_type = this_user.billing_type
    error_message = nil

    result = begin
      this_user.switch_billing_type_to_card(current_user)
    rescue User::CardConverter::ConvertError => err
      error_message = err.message
      false
    end

    if result
      # This instrument call sends data to the Audit Log.
      # There is a similar instrumentation in User#switch_billing_type_to_card
      # that logs to Hydro but it does not have access to the stafftools controller context.
      instrument("billing.change_billing_type", old_billing_type: old_type,
                billing_type: this_user.billing_type, user: this_user)
      flash[:notice] = "Successfully switched @#{this_user} to self-serve billing."
    else
      flash[:error] = "Failed to switch @#{this_user} to self-serve billing: #{error_message}"
    end

    redirect_to :back
  end

  sig { void }
  def change_plan # rubocop:todo GitHub/UseRestfulActions
    current_user = T.must(self.current_user)
    return render_404 if this_user.delegate_billing_to_business?

    old_seat_count = this_user.seats
    old_plan = this_user.plan
    old_plan_duration = this_user.plan_duration
    old_plan = this_user.plan
    old_seat_count = this_user.seats
    this_user.billing_extra = params[:billing_extra] if params[:billing_extra]
    this_user.billing_type  = params[:billing_type]  if params[:billing_type]

    result = if params[:seats]
      GitHub::Billing.change_seats \
        this_user,
        actor: current_user,
        seats: params[:seats].to_i,
        plan_duration: params[:plan_duration],
        collect_payment_job_id: synchronous_payment_collection_job_status.id
    elsif params[:plan] || params[:plan_duration]
      GitHub::Billing.change_subscription \
        this_user,
        actor: current_user,
        plan: params[:plan],
        plan_duration: params[:plan_duration],
        job_status_id: synchronous_payment_collection_job_status.id
    else
      GitHub::Billing::Result.success
    end

    if params[:plan]
      analytics_event(
        **organization_plan_change_ga_event_attributes(
          result.success?,
          this_user,
          current_user,
          old_plan,
          params[:plan] || old_plan,
          old_seat_count,
          params[:seats].present? ? params[:seats].to_i : old_seat_count
        )
      )
    end

    job_url = if should_show_synchronous_payment_collection_upgrading_page?
      job_status_url(synchronous_payment_collection_job_status.id)
    else
      ""
    end

    if result.success?
      if this_user.save
        if old_plan_duration != this_user.plan_duration
          this_user.track_plan_duration_change(current_user, old_plan_duration)
        end

        if params[:seats]
          publish_billing_seat_count_change_for(
            actor: current_user,
            user: this_user,
            old_seat_count: old_seat_count,
            new_seat_count: this_user.seats,
          )
        end

        # For synchronous payment collection, the notice is handled separately since the
        # result depends on the completion of a job that is performed later
        flash[:notice] = "Plan changed" unless job_url.present?
      else
        flash[:error] = "Error changing plan: #{this_user.errors.full_messages.join}"
      end
    else
      flash[:error] = "Error changing plan: #{result.error_message}"
    end

    respond_to do |format|
      format.json do
        render json: {
          job_url: job_url
        }
      end
      format.all do
        redirect_to :back
      end
    end
  end

  sig { void }
  def lock_billing # rubocop:todo GitHub/UseRestfulActions
    this_user.disable!(send_email: params[:send_email] ? true : false)

    flash[:notice] = "User locked"
    redirect_to :back
  end

  sig { void }
  def unlock_billing # rubocop:todo GitHub/UseRestfulActions
    this_user.unlock_billing!

    flash[:notice] = "User unlocked"
    redirect_to :back
  end

  sig { void }
  def sync_external_subscription # rubocop:todo GitHub/UseRestfulActions
    if this_user.invoiced? && !this_user.sponsors_invoiced?
      flash[:notice] = "Invoiced subscriptions cannot be synced."
    else
      this_user.create_or_update_external_subscription!(force: true)
      flash[:notice] = "External subscription sychronization enqueued."
    end
    redirect_to :back
  end

  sig { void }
  def sync_account_information # rubocop:todo GitHub/UseRestfulActions
    Billing::SynchronizeAccountInformationJob.perform_later(this_user)
    flash[:notice] = "Account information sychronization enqueued."
    redirect_to :back
  end

  sig { void }
  def sync_contact_information # rubocop:todo GitHub/UseRestfulActions
    customer = this_user.customer
    if customer.nil?
      flash[:warning] = "No customer exists for this account"
      redirect_to :back
    end
    contact = Billing::Contact.find_by(id: params[:contact_id])
    if contact.nil? || !contact.persisted?
      flash[:warning] = "No contact was found"
      redirect_to :back
    end
    if this_user.trade_screening_record.vat_code.present?
      this_user.trade_screening_record.sync_vat_code
    end
    T.must(contact).update_zuora_account_information(customer:)
    flash[:notice] = "Contact information synchronization enqueued."
    redirect_to :back
  end

  sig { void }
  def reset_billing_attempts # rubocop:todo GitHub/UseRestfulActions
    this_user.reset_billing_attempts

    ::Billing::Zuora::ResetPaymentMethodConsecutiveFailures.new(payment_method: this_user.payment_method).perform

    flash[:notice] = "Billing attempts reset"
    redirect_back(fallback_location: billing_stafftools_user_path(this_user))
  end

  sig { void }
  def run_pending_changes # rubocop:todo GitHub/UseRestfulActions
    plan_change =
      if params[:pending_change_id]
        this_user.pending_plan_changes.find_by(id: params[:pending_change_id])
      else
        this_user.pending_cycle_change
      end

    unless plan_change
      flash[:error] = "No pending plan change was found for #{this_user}"
      return redirect_to :back
    end

    if plan_change.run
      flash[:notice] = "Pending plan changes were successfully applied for #{this_user}."
    else
      flash[:error] = "Unable to run pending plan changes: #{plan_change.errors.full_messages.join(", ")}"
    end

    redirect_to :back
  end

  sig { void }
  def invoiced # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/users/invoiced", locals: { invoiced_accounts: User.invoiced.order("billed_on asc") }
  end

  sig { void }
  def update_bill_cycle_day # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_user.delegate_billing_to_business?

    new_bill_cycle_day = params[:bill_cycle_day].to_i
    if new_bill_cycle_day.zero?
      flash[:error] = "Invalid bill cycle day, can't be zero"
      redirect_to billing_stafftools_user_path(this_user)
      return
    end

    if !this_user.customer
      flash[:error] = "Unable to update bill cycle day, user has no customer"
    else
      result = ::Billing::UpdateCustomerBillCycleDay.new(this_user, new_bill_cycle_day, purpose: customer_purpose).call
      if result.success
        flash[:notice] = "Bill cycle day updated successfully"
      else
        flash[:error] = result.error_message
      end
    end

    redirect_to billing_stafftools_user_path(this_user)
  end

  # Skip billing checks for :packages and :storage for an year.
  # Adds a comment in the github/gitcoin/issues/4042 issue for tracking
  sig { void }
  def stop_billing_check # rubocop:todo GitHub/UseRestfulActions
    stop_billing_check_helper(this_user, T.must(current_user))
  end

  sig { void }
  def edit_extra_billing_info # rubocop:todo GitHub/UseRestfulActions
    this_user.billing_extra = params[:extra_billing_info] if params[:extra_billing_info]
    this_user.save

    flash[:notice] = "Extra billing info updated"
    redirect_to :back
  end

  sig { void }
  def change_seat_limit_for_upgrades # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_user.delegate_billing_to_business?

    unless this_user.organization?
      flash[:error] = "Cannot set seat limit for upgrades on a non-organization"
      redirect_to :back
      return
    end

    limit = params[:limit].to_i
    if limit <= 0
      flash[:error] = "Seat limit for upgrades must be a number greater than 0"
    elsif limit == this_user.default_seat_limit_for_upgrades
      # If the limit is the same as the default, we can just remove the custom limit.
      # This allows us to remove the database entry so we aren't wasting space unnecessarily.
      this_user.delete_custom_seat_limit_for_upgrades(current_user)
      this_user.save
      flash[:notice] = "Seat limit for upgrades has been reset to the default value"
    else
      this_user.set_custom_seat_limit_for_upgrades(limit, current_user)
      this_user.save
      flash[:notice] = "Seat limit for upgrades has been set to #{limit}"
    end
    redirect_to :back
  end

  sig { void }
  def update_metered_via_azure # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_user.delegate_billing_to_business?

    unless this_user.organization?
      flash[:error] = "Cannot update metered via Azure on a non-organization"
      redirect_to :back
      return
    end

    if !this_user.customer
      flash[:error] = "Unable to update metered via Azure on an organization without a customer"
    else
      customer = this_user.customer
      customer.metered_via_azure = params[:metered_via_azure] || false
      customer.save

      flash[:notice] = "Metered via Azure successfully updated"
    end

    redirect_to :back
  end

  sig { void }
  def update_azure_subscription # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_user.delegate_billing_to_business?

    unless this_user.organization?
      flash[:error] = "Cannot update Azure subscription on a non-organization"
      redirect_to :back
      return
    end

    unless this_user.invoiced?
      flash[:error] = "Cannot update Azure subscription on a non-invoiced organization"
      redirect_to :back
      return
    end

    if !this_user.customer
      flash[:error] = "Unable to update Azure subscription on an organization without a customer"
    else
      customer = this_user.customer
      customer.azure_subscription_id = params[:azure_subscription_id]

      if customer.save
        flash[:notice] = "Azure subscription successfully updated"
      else
        flash[:error] = "Failed to update Azure subscription: #{customer.errors.full_messages.join(", ")}"
      end
    end

    redirect_to :back
  end

  private

  sig do
    params(
      actor: ::User,
      user: ::User,
      new_seat_count: Integer,
      old_seat_count: Integer,
    ).void
  end
  def publish_billing_seat_count_change_for(actor:,
                                            user:,
                                            new_seat_count: 0,
                                            old_seat_count: 0)
    GlobalInstrumenter.instrument(
      "billing.seat_count_change",
      actor_id: actor.id,
      user_id: user.id,
      old_seat_count: old_seat_count,
      new_seat_count: new_seat_count,
    )
  end

  sig { returns(Symbol) }
  def sponsorships_tab
    params[:sponsorships_tab] == "past" ? :past : :current
  end

  sig { returns(::Billing::SharedStorageUsage) }
  memoize def shared_storage_usage
    Billing::SharedStorageUsage.usage_quote(this_user)
  end
  helper_method :shared_storage_usage

  sig { returns(::Billing::Money) }
  memoize def purchased_prepaid_metered_usage_refills
    Billing::Money.new(Billing::PrepaidMeteredUsageRefill.total_active_amount_in_cents_for(owner: this_user))
  end
  helper_method :purchased_prepaid_metered_usage_refills

  sig { returns(::Billing::Money) }
  memoize def remaining_prepaid_metered_usage_refills
    this_user.customer&.credit_balance || ::Billing::Money.zero
  end
  helper_method :remaining_prepaid_metered_usage_refills

  sig { returns(Symbol) }
  def customer_purpose
    purpose = params[:customer_purpose]
    return :sponsors if purpose.present? && purpose.to_sym == :sponsors

    Customer::DEFAULT_PURPOSE
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(T::Array[T.untyped]) }
  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  sig { returns(T::Array[T.untyped]) }
  def enabled_products
    enabled_products = this_user.customer.products_billed_via_billing_platform
    # enabled_products is an array of strings, so we need to get all products from bp since we need friendly names for the UI
    all_products.select { |product| enabled_products.include?(product[:name]) }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params
    all_params.except(:loadDiscount)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def all_params
    # todo: revisit user_id
    params.except(:slug).permit(:customer_id, :period, :product, :query, :group, :loadDiscount, :page, :user_id).to_h.symbolize_keys
  end

  sig { returns(::Billing::Types::Account) }
  memoize def this_entity
    this_user
  end

  sig { void }
  def ensure_vnext_enabled
    render_404 unless this_entity.customer&.billed_via_billing_platform?
  end

  sig { returns(String) }
  def react_layout
    is_org? ? "organization_settings" : "user_settings"
  end

  sig { returns(T::Boolean) }
  def is_org?
    this_entity.is_a?(Organization)
  end

  sig { returns(String) }
  def customer_id
    T.must(this_entity.customer).id.to_s
  end
end
