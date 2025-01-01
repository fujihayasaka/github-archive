# typed: true
# frozen_string_literal: true

class SubscriptionItemsController < ApplicationController
  include BillingSettingsHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:preview_change_duration]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:preview_change_duration], optional: true

  before_action :disable_color_modes
  before_action :ensure_billing_enabled

  before_action :login_required

  before_action :this_subscription_item_required
  before_action :this_subscription_item_admin_required
  before_action :ensure_non_sponsorship_subscription_item

  before_action :ensure_duration_change_only_for_product_uuid,
    :ensure_new_duration_exists,
    :ensure_product_uuid_is_available_for_new_duration,
    only: [:preview_change_duration, :update_duration]

  before_action :add_paypal_csp_exceptions, only: [:preview_change_duration]

  def update_duration # rubocop:todo GitHub/UseRestfulActions
    update = Billing::SubscriptionItemUpdater.perform(
      subscribable: new_duration_product_uuid,
      quantity: this_subscription_item.quantity,
      sender: current_user,
      plan_subscription: current_user.plan_subscription,
    )
    if update.result.success
      if update.change_scheduled
        flash[:notice] = "Your #{new_duration_product_uuid.name} subscription's duration change has been scheduled."
      else
        flash[:notice] = "Your subscription to #{new_duration_product_uuid.name} has been updated to #{new_duration}ly duration."
      end
    else
      flash[:error] = update.result.errors.first
    end

    redirect_to target_billing_path(current_user)
  end

  def preview_change_duration # rubocop:todo GitHub/UseRestfulActions
    plan_subscription = this_subscription_item.plan_subscription || current_user.plan_subscription
    updater = Billing::SubscriptionItemUpdater.new(
      subscribable: new_duration_product_uuid,
      quantity: this_subscription_item.quantity,
      sender: current_user,
      plan_subscription: plan_subscription,
    )

    render "subscription_items/preview_change_duration", locals: {
      subscription_item: this_subscription_item,
      new_duration: new_duration,
      new_duration_base_price: this_subscription_item.base_price(duration: new_duration),
      payment_due_date: updater.update_execution_date,
      # TODO: This is not calculating prorated/credit values and instead is showing the full amount is due
      # Zuora will correctly charge the correct prorated/credited value when the change happens
      next_payment_amount: this_subscription_item.price(duration: new_duration, service_remaining: 1),
      hide_name_address_collection_wrapper: hide_name_address_collection_wrapper?
    }
  end

  def destroy
    if this_subscription_item.cancelled?
      flash[:error] = "This item has already been cancelled."
    else
      this_subscription_item.cancel!(actor: current_user, force: false).result
      submit_survey
      flash[:billing_flash_notice] = cancellation_notice
    end

    redirect_to params[:redirect_to] || :back
  end

  private

  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }

    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end

  memoize def new_duration_product_uuid
    Billing::ProductUUID.find_by(
      product_type: this_subscription_item.subscribable.product_type,
      product_key: this_subscription_item.subscribable.product_key,
      billing_cycle: new_duration
    )
  end

  memoize def new_duration
    if this_subscription_item.monthly?
      "year"
    elsif this_subscription_item.yearly?
      "month"
    end
  end

  def ensure_product_uuid_is_available_for_new_duration
    unless new_duration_product_uuid
      flash[:error] = "This product is not available for #{new_duration} duration"
      redirect_to target_billing_path(current_user)
    end
  end

  def ensure_new_duration_exists
    unless new_duration
      flash[:error] = "This subscription item is not eligible for duration change"
      redirect_to target_billing_path(current_user)
    end
  end

  def ensure_duration_change_only_for_product_uuid
    unless this_subscription_item.subscribable_Billing_ProductUUID?
      flash[:error] = "This subscription item is not eligible for duration change"
      redirect_to target_billing_path(current_user)
    end
  end

  def hide_name_address_collection_wrapper?
    current_user.has_saved_billing_information?
  end

  def target_for_conditional_access
    # CAP is not needed if item is nil. We'd 404 unless user is logged in and can admin the item.
    return :no_target_for_conditional_access unless this_subscription_item.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    this_subscription_item.plan_subscription&.billable_entity
  end

  def cancellation_notice
    subscribable = this_subscription_item.subscribable
    subscribable_name = subscribable.name

    if this_subscription_item.subscribable_Billing_ProductUUID?
      notice = "You've cancelled your subscription to #{subscribable_name}."
    else # Marketplace
      listing = subscribable.listing
      listing_name = listing.name
      notice = "You've cancelled your subscription to #{subscribable_name} for #{listing_name}."
    end

    extended_notice = " This plan change will take effect on"

    # Subscription items that are a Product UUID do not cancel immediately, marketplace and sponsorships do
    # this is a legacy bug that will be addressed in an immediate follow up PR.
    if this_subscription_item.on_free_trial? && this_subscription_item.subscribable_Billing_ProductUUID?
      next_billing_date = this_subscription_item.free_trial_ends_on.to_formatted_s :date
      notice += "#{extended_notice} #{next_billing_date}."
    elsif !this_subscription_item.on_free_trial?
      next_billing_date = this_subscription_item.account.next_billing_date.to_formatted_s :date
      notice += "#{extended_notice} #{next_billing_date}."
    end

    notice
  end

  memoize def this_subscription_item
    if params[:subscription_item_id]
      current_user.active_subscription_items.find_by(id: params[:subscription_item_id])
    else
      typed_object_from_id([Platform::Objects::SubscriptionItem], params[:id])
    end
  rescue Platform::Errors::NotFound
    nil
  end

  def this_subscription_item_required
    render_404 unless this_subscription_item
  end

  def this_subscription_item_admin_required
    return if current_user.site_admin?
    return if this_subscription_item.adminable_by?(current_user)
    render_404
  end

  def ensure_non_sponsorship_subscription_item
    return unless GitHub.sponsors_enabled? && this_subscription_item.subscribable_SponsorsTier?

    sponsorable = this_subscription_item.sponsorable
    sponsor = this_subscription_item.account
    whose_sponsorship = sponsor == current_user ? "your" : "#{sponsor}'s"

    if params[:action] == "destroy"
      flash[:error] = "You can cancel #{whose_sponsorship} sponsorship of #{sponsorable} via billing settings."
      if sponsor.organization?
        redirect_to settings_org_billing_path(sponsor, sponsorships_tab: "current", anchor: "sponsorship-history")
      else
        redirect_to settings_user_billing_path(sponsorships_tab: "current", anchor: "sponsorship-history")
      end
    else
      flash[:error] = "Please change #{whose_sponsorship} sponsorship tier via #{sponsorable}'s Sponsors profile."
      redirect_to edit_sponsorable_sponsorships_path(sponsorable, sponsor: sponsor)
    end
  end

  def submit_survey
    return unless survey_answers.any? && params[:survey_id].present?
    SurveyAnswer.save_as_group(current_user.id, params[:survey_id], survey_answers)
  end

  memoize def survey_answers
    Array(params[:answers]&.values).select do |answer|
      next false unless answer[:choice_id].present?

      # Ignore answers of empty text
      answer.key?(:other_text) ? answer[:other_text].present? : true
    end.map { |sa| sa.permit(:question_id, :choice_id, :other_text).to_h }
  end
end
