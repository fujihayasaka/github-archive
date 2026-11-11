# typed: strict
# frozen_string_literal: true

class Stafftools::SubscriptionItemsController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests

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

  layout :layout

  before_action :ensure_billing_enabled
  before_action :ensure_account_exists

  sig { void }
  def index
    render "stafftools/subscription_items/index", locals: {
      active_items: active_product_uuid_subscription_items,
      cancelled_items: past_product_uuid_subscription_items
    }
  end

  sig { void }
  def show
    item = product_uuid_subscription_items.detect { |item| item.id == params[:id].to_i }
    return render_404 unless item
    render "stafftools/subscription_items/show", locals: {
      item: item
    }
  end

  sig { void }
  def destroy
    item = Billing::SubscriptionItem.find(params[:id])
    allowed_accounts = account.is_a?(User) ? [account, account.billable_owner].compact : [account]
    unless item.account.in?(allowed_accounts)
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

  sig { returns(String) }
  def layout
    account = self.account
    if account.is_a?(Business)
      "layouts/stafftools/business"
    else
      if account.site_admin_context == "organization"
        "layouts/stafftools/organization/billing"
      else
        "layouts/stafftools/user/billing"
      end
    end
  end

  sig { params(item: ::Billing::SubscriptionItem).void }
  def cancel_and_refund(item)
    Billing::Public::SubscriptionItem.cancel_and_refund(product: item.subscribable, account: T.must(item.account), allow_cancelling_iap: true)

    flash[:notice] = "Subscription cancellation & refund to #{item.subscribable.name} enqueued"

    redirect_to :back
  end

  sig { returns(Billing::Types::Account) }
  memoize def account
    this_business || T.cast(this_user, User)
  end
  helper_method :account

  sig { returns(T.nilable(Business)) }
  memoize def this_business
    return nil unless params[:enterprise_slug] || params[:slug]
    slug = params[:enterprise_slug] || params[:slug]
    ::Business.find_by(slug: slug)
  end
  helper_method :this_business

  sig { void }
  def ensure_account_exists
    if this_business
      render_404 unless this_business.present?
    else
      ensure_user_exists
    end
  end

  # Get subscription items based on account type
  sig { returns(T::Array[Billing::SubscriptionItem]) }
  def product_uuid_subscription_items
    account = self.account
    if account.is_a?(Business)
      account.plan_subscription&.product_uuid_subscription_items || Billing::SubscriptionItem.none
    else
      account.product_uuid_subscription_items
    end.to_a
  end

  sig { returns(T::Array[Billing::SubscriptionItem]) }
  def active_product_uuid_subscription_items
    account = self.account
    if account.is_a?(Business)
      account.plan_subscription.try(:active_product_uuid_subscription_items) || Billing::SubscriptionItem.none
    else
      account.active_product_uuid_subscription_items
    end.to_a
  end

  sig { returns(T::Array[Billing::SubscriptionItem]) }
  def past_product_uuid_subscription_items
    account = self.account
    if account.is_a?(Business)
      account.plan_subscription.try(:past_product_uuid_subscription_items) || Billing::SubscriptionItem.none
    else
      account.past_product_uuid_subscription_items
    end.to_a
  end
end
