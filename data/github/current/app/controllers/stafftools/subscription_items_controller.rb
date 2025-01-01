# typed: true
# frozen_string_literal: true

class Stafftools::SubscriptionItemsController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  depends_on_clusters ApplicationRecord::Ballast,
                      ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::IssuesPullRequests,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories,
                      only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
                      only: [:index, :show], optional: true

  layout :billing_layout

  before_action :ensure_billing_enabled
  before_action :ensure_user_exists

  def index
    render "stafftools/subscription_items/index", locals: {
      active_items: this_user.active_product_uuid_subscription_items,
      cancelled_items: this_user.past_product_uuid_subscription_items
    }
  end

  def show
    render "stafftools/subscription_items/show", locals: {
      item: this_user.product_uuid_subscription_items.find(params[:id])
    }
  end

  def destroy
    item = Billing::SubscriptionItem.find(params[:id])
    if !item.account.in?([this_user, this_user.billable_owner].compact)
      flash[:error] = "Subscription item not found or you do not have permission to cancel it."
      redirect_to params[:redirect_to] || :back
      return
    end

    if item.sponsorship.present?
      flash[:error] = "Please use `cancelSponsorship` to cancel a sponsorship."
      redirect_to params[:redirect_to] || :back
      return
    end

    if item.cancelled?
      flash[:error] = "This subscription is already cancelled."
      redirect_to params[:redirect_to] || :back
      return
    end

    if params[:operation] == "cancel_and_refund" && item.in_app_purchase?
      flash[:error] = "In-app purchased subscriptions cannot be cancelled and refunded."
      redirect_to params[:redirect_to] || :back
      return
    elsif params[:operation] == "cancel_and_refund"
      return cancel_and_refund(item)
    end

    outcome = item.cancel!(actor: current_user, force: true, allow_cancelling_iap: true).result
    if outcome.success
      subscribable = item.subscribable
      subscribable_name = subscribable.name

      if item.subscribable_Billing_ProductUUID?
        notice = "You've cancelled the subscription to #{subscribable_name}."
      else
        listing_name = subscribable.listing.name
        notice = "You've cancelled the subscription to #{subscribable_name} for #{listing_name}."
      end

      flash[:notice] = notice
    else
      flash[:error] = outcome.errors.join(", ")
    end

    redirect_to params[:redirect_to] || :back
  end

  private

  def cancel_and_refund(item)
    Billing::Public::SubscriptionItem.cancel_and_refund(product: item.subscribable, account: item.account, allow_cancelling_iap: true)

    flash[:notice] = "Subscription cancellation & refund to #{item.subscribable.name} enqueued"

    redirect_to :back
  end
end
