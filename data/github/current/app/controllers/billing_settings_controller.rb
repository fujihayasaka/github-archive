# typed: true
# frozen_string_literal: true

class BillingSettingsController < ApplicationController
  include BillingSettingsHelper
  include BusinessesHelper
  include OrganizationsHelper
  include TradeControlsControllerMethods
  include SurveyHelper
  include PlanDowngradeHelper

  include GitHub::Memoizer

  # Always render a 404 when billing is disabled.
  # See Application#ensure_billing_enabled.
  before_action :ensure_billing_enabled, except: [:spending_limit]
  before_action :ensure_trade_restrictions_allows_org_settings_access, only: [:user_billing, :spending_limit]

  before_action :login_required
  before_action only: [:upgrade] do
    T.bind(self, BillingSettingsController)
    check_trade_compliance(target: target)
  end
  before_action :ensure_actor_can_change_plan, only: [:cc_update]
  before_action only: :spending_limit do
    T.bind(self, BillingSettingsController)
    check_trade_compliance(feature_type: :cost_management, sdn_redirect: true)
  end
  before_action :ensure_target, except: [:user_billing, :spending_limit]
  before_action :ensure_target_is_billable, except: [:user_billing, :spending_limit]

  javascript_bundle :signup
  javascript_bundle :"billing-settings"

  stylesheet_bundle :settings

  rescue_from ::Timeout::Error, with: :payment_processor_error

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:user_billing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:upgrade]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:receipt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:downgrade_features_count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:plans]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:client_token]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:lfs_bandwidth_breakdown]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:lfs_storage_breakdown]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:payment_history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:user_profile_view]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:upgrade, :downgrade_features_count, :plans, :client_token],
    optional: true

  # Update the VAT ID and extra freeform text that appears on receipts.
  def extra_update # rubocop:todo GitHub/UseRestfulActions
    billing_extra = params[:billing_extra]&.strip
    vat_code = params[:vat_code]&.strip

    target.update(billing_extra: billing_extra)
    flash_text = "Updated your optional contact information, it will show up on your next receipt."
    error = false

    if !vat_code.nil? && target.customer.present?
      target.customer.update \
        vat_code: params[:vat_code].strip

      if zuora_account_id = target.customer.zuora_account_id
        response = GitHub.zuorest_client.update_account(
          zuora_account_id,
          {
            taxInfo: {
              VATId: vat_code
            }
          },
          { "Content-Type" => "application/json" }
        )
        response = GitHub::Billing::Result.from_zuora(response)
        unless response.success?
          error = true
          flash_text = "An error occurred while saving your contact information. Please try again."
        end
      end
    end

    if error
      flash[:error] = flash_text
    else
      flash[:notice] = flash_text
    end

    redirect_to billing_path
  end

  def client_token # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    render plain: GitHub::Billing.generate_braintree_client_token.to_s
  end

  def payment_history # rubocop:todo GitHub/UseRestfulActions
    render "billing_settings/payment_history", locals: {
      target: target,
      iap: Billing::Public::InAppPurchasing.new(target),
      payment_records: Billing::Settings::PaymentHistory::PaymentRecord.payment_records(
        target: target
      )
    }
  end

  def receipt # rubocop:todo GitHub/UseRestfulActions
    transaction = target.billing_transactions.find_by_transaction_id(params[:id])

    if transaction && transaction.success?
      @receipt = ::Billing::Receipt.new(transaction)
      respond_to do |format|
        format.text do
          render "mailers/billing_notifications/receipt"
        end
        format.pdf do
          send_data(@receipt.to_pdf,
            filename: @receipt.pdf_filename,
            type: "application/pdf",
            disposition: "inline",
          )
        end
        format.html do
          send_data(@receipt.to_pdf,
            filename: @receipt.pdf_filename,
            type: "application/pdf",
            disposition: "attachment",
          )
        end
      end
    else
      render_404
    end
  end

  # If the user has an external customer record (e.g. Braintree customer or
  # Zuora account), then update their existing credit card on file. Otherwise,
  # create a new external customer record with the given credit card details.
  def update_credit_card # rubocop:todo GitHub/UseRestfulActions
    return render_404 if target.business

    if target.invoiced?
      flash[:error] = "Cannot set credit card payment option for invoiced organization or enterprise."
      return redirect_to :back
    end

    if no_payment_details?
      flash[:error] = "Please enter your payment information."
      redirect_to :back
    else
      details = payment_details.merge(actor: current_user)

      result = if plan_status.plan_changed?
        ga_params = set_ga_params
        payment_difference = payment_difference_for_new_plan(target, params[:plan])
        change_plan_result = change_plans(target, params[:plan], details)
        change_plan_result
      else
        set_payment_method(target, details)
      end

      if result.success?
        updated_or_added = target.has_credit_card? ? "updated" : "added"

        publish_payment_method_changed_for(
          actor: current_user,
          account: target,
          payment_method: target.payment_method,
        )

        if payment_details_includes_paypal?
          flash[:notice] = "Your PayPal account has been successfully added."
        elsif session[:copilot_flash_pay_info_message].present?
          flash[:copilot_notice_message] = "Your credit card has been successfully #{updated_or_added}."
          session.delete(:copilot_flash_pay_info_message)
          GlobalInstrumenter.instrument(
            "analytics.event",
            category: "new_org_copilot_add_on",
            action: "free_org_update_credit_card",
            label: "flash_message:credit_card_updated;",
          )
        else
          flash[:notice] = "Your credit card has been successfully #{updated_or_added}."
        end

        if plan_status.plan_changed?
          flash[:notice] += " Your request for changing plans to #{target.plan.display_name} was also successful."
          flash[:analytics_location_params] = ga_params
        end

        analytics_event_for_plan_change(payment_difference) if plan_status.cost_changed?

        if params[:return_to].present?
          safe_redirect_to params[:return_to], fallback: billing_path
        else
          redirect_to billing_path
        end
      else
        error_message = result.error_message

        GitHub.context.push(error: error_message.to_s)
        Audit.context.push(error: error_message.to_s)

        if error_message.respond_to?(:metadata)
          GitHub.context.push(metadata: error_message.metadata)
          Audit.context.push(metadata: error_message.metadata)
        end

        flash[:error] = error_message.to_s
        redirect_to target_payment_method_path(target)
      end
    end
  end

  # Update plan_duration (monthly or yearly billing cycle).
  def cycle_update # rubocop:todo GitHub/UseRestfulActions
    result = Billing::CycleUpdate.perform(target, params[:plan_duration], actor: current_user)

    if result.success?
      flash[:notice] = "Your request to change to #{target.pending_cycle_plan_duration}ly billing was successful."
    else
      flash[:error] = "#{result.error_message} #{GitHub.support_link_text}."
    end

    redirect_to billing_path
  end

  def plans # rubocop:todo GitHub/UseRestfulActions
    return render_404 if current_user.is_enterprise_managed?
    return redirect_to settings_billing_enterprise_path(target.business, org_plan_select: true) if target.organization? && target.business.present?

    @survey = find_survey
    render "billing_settings/plans"
  end

  def upgrade # rubocop:todo GitHub/UseRestfulActions
    if target.no_verified_emails?
      flash[:error] = "At least one email address must be verified to upgrade your plan"
      return redirect_to target_billing_path(target)
    end

    if target.spammy?
      flash[:error] = "You cannot upgrade your plan because your account has been flagged. If you believe this is a mistake, contact support"
      return redirect_to target_billing_path(target)
    end

    duration = params[:plan_duration] || User::BillingDependency::YEARLY_PLAN
    plan = GitHub::Plan.find(params[:plan])
    plan ||= target.organization? ? GitHub::Plan.business : GitHub::Plan.pro

    if target.organization? && target.upgrade_to_enterprise_in_progress?
      upgrade_status = if target.upgrade_to_enterprise_in_progress.organization_upgrade_initiated?
        "Return to the checkout page to complete or cancel the upgrade"
      else
        "Please wait until the payment has finished processing"
      end
      flash[:error] = "You cannot change your plan because this organization is currently being upgraded to an Enterprise Account. #{upgrade_status}."
      return redirect_to :back
    end

    # If the target is an enterprise-managed organization and the enterprise has an expired trial,
    # the upgrade should be performed on the parent enterprise and not the organization
    if target.organization? && target.business.present? && target.business.trial_expired?
      return redirect_to billing_settings_upgrade_enterprise_path(target.business)
    end

    unless valid_plan_or_duration_change?(plan)
      return redirect_to billing_path
    end

    plan_change =
      if target.organization?
        Billing::PlanChange::PerSeatPricingModel.new(
          target,
          plan_duration: duration,
          new_plan: plan,
          seats: seat_count,
          plan_and_seat_cost_only: true,
        )
      else
        Billing::PlanChange.new \
          target.subscription,
          Billing::Subscription.for_account(
            target,
            plan: plan,
            duration_in_months: duration == User::BillingDependency::MONTHLY_PLAN ? 1 : 12,
          ),
          starting_new_subscription: !target.external_subscription?,
          plan_and_seat_cost_only: true
      end

    if params[:return_to].present?
      return_to = params[:return_to]
    else
      return_to = params[:return_to] = request.url
    end

    respond_to do |format|
      format.html do
        instrument_loaded_page

        view = BillingSettings::ConfirmationView.new(
          account: target,
          plan_change: plan_change,
          return_to: return_to,
          actor: current_user
        )
        show_team_as_link = view.upgrade_to_team_as_link?(logged_in: logged_in?, source: params[:source])
        page_title = view.action_text(show_team_as_link: show_team_as_link)

        if target.organization?
          render "billing_settings/upgrade_org_dynamic_seats", locals: {
            selected_duration: duration,
            view: view,
            target: target,
            return_to: return_to,
            show_team_as_link: show_team_as_link,
            data_collection_enabled: view.data_collection_enabled?,
            page_title: page_title
          }
        else
          render "billing_settings/upgrade", locals: {
            view: view,
            target: target,
            return_to: return_to,
            show_team_as_link: show_team_as_link,
            data_collection_enabled: view.data_collection_enabled?,
            page_title: page_title
          }
        end
      end
      format.json do
        render json: upgrade_json(plan_change)
      end
    end
  end

  # Change plan and apply coupon.
  def cc_update # rubocop:todo GitHub/UseRestfulActions
    ga_params = set_ga_params
    details = payment_details.merge(actor: current_user)
    payment_difference = payment_difference_for_new_plan(target, params[:plan])
    result = change_plans(target, params[:plan], details, params[:plan_duration], synchronous_payment_collection_job_status.id)

    old_plan = GitHub::Plan.find(old_plan_name)
    new_plan = GitHub::Plan.find(new_plan_name)

    # Render the upgrading page if we are collecting payment synchronously for this change
    if should_show_synchronous_payment_collection_upgrading_page?
      render "billing_upgrade/upgrading", locals: {
        job_status_id: synchronous_payment_collection_job_status.id,
        new_plan: new_plan,
        new_seats: nil,
        old_plan: old_plan,
        old_seats: nil,
        price: payment_difference,
        seat_delta: nil,
        target: target
      }
    elsif result.success?
      msg = target.pending_cycle_change ? "will be" : "has been"
      flash[:notice] = "The plan change was successful. @#{target.display_login} #{msg} updated to the #{target.pending_cycle_plan.display_name} #{target.pending_cycle_plan_duration}ly plan."
      flash[:analytics_location_params] = ga_params
      analytics_event_for_plan_change(payment_difference) if plan_status.cost_changed?

      redirect_to billing_path
    else
      flash[:error] = "#{result.error_message} #{GitHub.support_link_text}."

      if target.over_repo_seat_limit?
        redirect_to settings_repositories_path
      else
        redirect_to billing_path
      end
    end
  end

  # Update a user's billing info or perform a payment update
  def billing_update # rubocop:todo GitHub/UseRestfulActions
    return update_trade_screening_record if params[:billing_info_submit_btn].present?

    cc_update
  end

  # Downgrade the plan and ask exit survey
  def downgrade_with_exit_survey # rubocop:todo GitHub/UseRestfulActions
    @plan = GitHub::Plan.find(params[:plan])
    @survey = find_survey

    SurveyAnswer.save_as_group(current_user.id, @survey.id, params[:answers])

    cc_update
  end

  def update_email # rubocop:todo GitHub/UseRestfulActions
    target.billing_email = params[:organization][:billing_email]

    if target.save
      flash[:notice] = "Successfully updated billing email for #{target.display_login}."
    else
      flash[:error] = target.errors.full_messages.to_sentence
    end

    redirect_to settings_org_billing_path(target)
  end

  private def target_for_conditional_access
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def downgrade_features_count # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request if params[:target] != "organization" && params[:target] != "user"

    results = {}
    repo_ids = target.private_repositories.pluck(:id)
    downgrade_features_with_counts(target).keys.each do |feature|
      next unless params[feature].present?

      count = count_for_downgrade_feature(feature, repo_ids)
      results[feature] = format_downgrade_feature_usage_count(count)
    end

    render json: { counts: results }
  rescue NoMethodError, NameError, ActiveRecord::RecordNotFound
    render json: { error: "Unable to read the request object" }, status: :not_found
  end

  SELECTED_LINKS = {
    "subscriptions" => :user_billing_settings,
    "past_invoices" => :user_billing_settings,
    "payment_information" => :payment_information,
    "spending_limit" => :spending_limits,
  }
  def user_billing # rubocop:todo GitHub/UseRestfulActions
    return render_404 if current_user.is_enterprise_managed?
    ActiveRecord::Base.connected_to(role: :writing) { current_user.expire_stale_coupon }

    if params[:coupon]
      redirect_to redeem_coupon_path params[:coupon]
    else
      tab = params[:tab]
      return render_404 if tab == "spending_limit" && !Billing::Budget.configurable?(current_user)

      sponsors_tab = Billing::Settings::SponsorsOverviewComponent::HistoryTab.try_deserialize(params[:sponsorships_tab])
      sponsors_tab ||= Billing::Settings::SponsorsOverviewComponent::HistoryTab::Current

      if pjax? && pjax_container == "#sponsors-section-pjax-container"
        render Billing::Settings::SponsorsOverviewComponent.new(user_or_org: current_user, active_tab: sponsors_tab)
      else
        context_region_preset :settings
        selected_link = SELECTED_LINKS.fetch(tab, :user_billing_settings)

        render "settings/user/billing", locals: {
          selected_tab: tab,
          sponsors_tab: sponsors_tab,
          selected_link: selected_link
        }
      end
    end
  end

  def spending_limit # rubocop:todo GitHub/UseRestfulActions
    owner = current_user
    return render_404 unless Billing::Budget.configurable?(owner)
    return render_404 unless Billing::Budget.valid_budget_group?(params[:budget_group])

    unless owner.has_valid_payment_method?
      flash[:error] = "You can’t increase the spending limits until you set up a valid payment method"
      redirect_to :back
      return
    end

    budget = owner.budget_for(group: params[:budget_group])
    budget.configure(
      enforce_spending_limit: params[:enforce_spending_limit] == "true",
      limit: params[:spending_limit].to_d,
    )

    if budget.errors.any?
      if budget.errors[:tiered_spending].present?
        flash[:error] = budget.errors[:tiered_spending].first
      else
        flash[:error] = "Unable to set a spending limit. Please check your payment method and limit"
      end
    else
      flash[:notice] = "Spending limit configuration has been updated"
    end

    redirect_to :back
  end

  def usage_notification_settings # rubocop:todo GitHub/UseRestfulActions
    owner = current_user
    return render_404 unless Billing::Budget.configurable?(owner)
    notification_params = usage_notification_params
    budget_group = notification_params[:budget_group]
    return render_404 unless Billing::Budget.valid_budget_group?(budget_group)

    budget = owner.budget_for(group: budget_group)
    status = budget.configure_notifications(
      included_usage_notification: notification_params[:included_usage_notification],
      paid_usage_notification: notification_params[:paid_usage_notification],
    )
    if request.xhr?
      head status ? :ok : :bad_request
    else
      if !status
        flash[:error] = "Unable to update notification settings."
      end
      redirect_to settings_user_billing_tab_path(tab: "spending_limit")
    end
  end

  def lfs_bandwidth_breakdown # rubocop:todo GitHub/UseRestfulActions
    render partial: "billing_settings/lfs_bandwidth_breakdown", locals: { target: target }
  end

  def lfs_storage_breakdown # rubocop:todo GitHub/UseRestfulActions
    render partial: "billing_settings/lfs_storage_breakdown", locals: { target: target }
  end

  private

  def ensure_actor_can_change_plan
    return unless logged_in?
    return unless target.has_commercial_interaction_restriction?

    plan_record = GitHub::Plan.find(params[:plan] || target.plan.try(:name))

    return unless plan_record.present?

    seats = plan_record.per_seat? ? target.seats : 0

    downgrading_plan = params[:plan] == "free" &&
      target.undiscounted_payment_difference(plan_record, seat_count: seats) < 0

    return if downgrading_plan

    flash[target.trade_screening_status_notice] = true

    if params[:return_to].present?
      safe_redirect_to params[:return_to], fallback: billing_path
    else
      redirect_to billing_path
    end
  end

  def valid_plan_or_duration_change?(plan)
    if changing_plan?(plan)
      target.can_change_plan_to?(plan)
    else
      changing_duration?
    end
  end

  def changing_plan?(plan)
    if plan == target.plan && Billing::EnterpriseCloudTrial.new(current_organization).active?
      true
    else
      plan != target.plan
    end
  end

  # Private: Change plans for the target.
  #
  # target          - A User or organization.
  # plan            - String plan name.
  # payment_details - A Hash of payment_details.
  # plan_duration   - (optional) String of "month" or "year".
  # job_status_id   - (optional) JobStatus ID to track the plan change progress.
  #
  # Returns a GitHub::Billing::Result.
  def change_plans(target, plan, payment_details, plan_duration = nil, job_status_id = nil)
    if target.has_billing_record? || plan == "free"
      GitHub::Billing.change_subscription(target, actor: current_user, plan: plan, payment_details: payment_details,
        plan_duration: plan_duration, job_status_id: job_status_id)
    else
      GitHub::Billing.paid_upgrade(target, plan, payment_details, plan_duration: plan_duration,
        actor: current_user)
    end
  end

  # Private: Update payment method on file for the target.
  #
  # target          - A User or organization.
  # payment_details - A Hash of payment_details.
  #
  # Returns a GitHub::Billing::Result.
  def set_payment_method(target, payment_details)
    timeout(28) do
      if target.has_billing_record?
        GitHub::Billing.update_payment_method(target, payment_details.merge(unlock_billing: true))
      else
        GitHub::Billing.create_customer(target, payment_details, actor: current_user)
      end
    end
  end

  def find_survey
    Survey.find_by(slug: "org_downgrade")
  end

  helper_method :target
  def billing_path(query_params = nil)
    target_billing_path(target, query_params)
  end

  sig { returns(Billing::PlanTransition) }
  memoize def plan_status
    Billing::PlanTransition.new(target, params[:plan])
  end

  # This gathers params for Google Analytics params and it has to be
  # called *before* the actual plan change happens, while the tracking
  # flash can only be set *after* the plan change has succeeded.
  def set_ga_params
    { target: plan_status.target_type,
      plan: plan_status.new_plan.name,
      billing: plan_status.billing?,
      action: plan_status.cost_change_label,
    }
  end

  # Ensures that GA custom events get fired:
  # "User: plan upgrade/downgrade"
  # "Orgs: plan upgrade/downgrade"
  def analytics_event_for_plan_change(payment_difference)
    analytics_ec_purchase(target, payment_difference, "Upgrade")

    analytics_event(
      category: (plan_status.organization? ? "Orgs" : "User"),
      action: "plan #{plan_status.cost_change_label}",
      label: "#{plan_status.old_plan.display_name} -> #{plan_status.new_plan.display_name}"
    )
  end

  # Calculate prorated payment difference of switching to a new plan
  #
  # Returns a BigDecimal amount in dollars
  def payment_difference_for_new_plan(target, new_plan_name)
    plan = GitHub::Plan.find(new_plan_name) || target.plan

    target.payment_difference plan, use_balance: true
  end

  def ensure_target
    render_404 if params[:target] && target.nil?
  end

  def target # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @target ||= target!
  end

  def target!
    if params[:target] == "business"
      business = Business.find_by(slug: params[:business_id])
      if business && (current_user_can_manage_settings(business) || business.billing_manager?(current_user))
        business
      end
    elsif params[:target] == "organization"
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  def ensure_target_is_billable
    render_404 unless target.billable?
  end

  def changing_duration?
    params[:plan_duration].present? && params[:plan_duration] != target.plan_duration
  end

  def payment_processor_error
    flash[:error] = "There was a problem communicating with our payment provider. Please try again."
    redirect_to :back
  end

  def old_plan_name
    plan_status.old_plan.name
  end

  def new_plan_name
    plan_status.new_plan.name
  end

  def publish_payment_method_changed_for(actor:, account:, payment_method:)
    GlobalInstrumenter.instrument(
      "billing.payment_method.addition",
      actor_id: actor.id,
      account_id: account.id,
      payment_method_id: payment_method.id,
    )
  end

  def upgrade_json(plan_change)
    view = BillingSettings::ConfirmationView.new(account: target, plan_change: plan_change)
    {
      seats: params[:seats],
      selectors: {
        ".unstyled-renewal-price" => view.renewal_list_price.format,
        ".unstyled-next-plan-price" => view.next_plan_price.format,
        ".unstyled-payment-due" => view.changing_duration? ? view.final_price(github_only: false).format : view.final_price(github_only: true).format,
      },
    }
  end

  def seat_count
    if target.upgrading_from_trial? || params[:seats]
      params[:seats] || Organization::LicenseAttributer.new(target).unique_count
    end
  end

  def usage_notification_params
    params.permit(:authenticity_token, :budget_group, :included_usage_notification, :paid_usage_notification)
  end

  def instrument_loaded_page
    # do not instrument if the plan is unchanged AND the new plan is free AND the plan param is not nil
    return if new_plan_name == old_plan_name && new_plan_name.casecmp?("free") && !params[:plan].nil?
    # do not instrument if the target has a saved trade screening record (form is not loaded just information show)
    return if target.has_saved_trade_screening_record?

    suffix = target.organization? ? "_TO_#{new_plan_name.upcase}" : ""
    instrument_billing_form_loaded(flow: "UPGRADE#{suffix}")
  end

  def initialize_hydro_context
    super

    if hydro_context && hydro_context[:enabled] && current_organization
      hydro_context.merge!({
        current_org: current_organization.name,
        current_org_id: current_organization.id,
      })
    end
  end
end
