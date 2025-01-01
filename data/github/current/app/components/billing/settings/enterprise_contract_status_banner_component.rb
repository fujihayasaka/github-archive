# typed: strict
# frozen_string_literal: true

class Billing::Settings::EnterpriseContractStatusBannerComponent < ApplicationComponent

  NOTICE_NAME = "sales_serve_enterprise_contract_status_notice"

  sig { returns(Business) }
  attr_reader :business

  sig { returns(User) }
  attr_reader :current_user

  sig { params(business: Business, current_user: User).void }
  def initialize(business:, current_user:)
    @business = T.let(business, Business)
    @current_user = T.let(current_user, User)
  end

  sig { returns(T::Boolean) }
  memoize def business_adminable_by_user?
    business.adminable_by?(current_user)
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless business.feature_enabled?(:ghe_sales_serve_renewals)
    return false unless business.invoiced?
    return false unless user_has_access?
    return false unless business.has_contract_change?
    return false unless user_has_unread_request_status?

    prepare_banner
  end

  sig { returns(T::Boolean) }
  memoize def is_billing_manager?
    business.billing_manager?(current_user)
  end

  sig { returns(T::Boolean) }
  def user_has_access?
    business_adminable_by_user? || is_billing_manager?
  end

  sig { returns(T.nilable(Symbol)) }
  attr_reader :color_scheme

  sig { returns(T.nilable(String)) }
  attr_reader :text

  sig { returns(T.nilable(String)) }
  attr_reader :action_text

  sig { returns(T.nilable(String)) }
  attr_reader :action_url

  sig { returns(T::Boolean) }
  def has_action?
    action_text.present? && action_url.present?
  end

  sig { returns(T::Boolean) }
  def user_has_unread_request_status?
    last_dismissed_timestamp = Growth::NoticeDismissal.new(current_user).dismissed_business_notice_at(NOTICE_NAME, business_id: T.must(business.id))
    return true unless last_dismissed_timestamp

    business.has_change_request_update_newer_than?(last_dismissed_timestamp)
  end

  sig { returns(ActiveSupport::TimeWithZone) }
  def dismissal_expires_at
    (Business::BillingContractUpdateDependency::CONTRACT_RENEWAL_WINDOW_LONG + 1.month).from_now
  end

  private

  sig { returns(T::Boolean) }
  def prepare_banner
    # Upgrade/renewal failed
    if business.has_any_failed_change_requests?
      transaction = business.has_any_failed_renewal_requests? ? "renewal" : "upgrade"
      @text = T.let("We were not able to process this #{transaction}. Please contact sales.", T.nilable(String))
      @color_scheme = T.let(:danger, T.nilable(Symbol))
      @action_text = T.let("Contact sales", T.nilable(String))
      @action_url = T.let("https://github.com/renewals-help", T.nilable(String))

      return true
    end

    if business.feature_enabled?(:ghe_sales_serve_upgrades) && business.renewal_has_seat_gap? && !business.in_lock_out_period?
      @text = T.let(
        safe_join([
          "Thank you for renewing GitHub Enterprise. Your new contract will start on ",
          content_tag(:strong, T.must(business.renewal_scheduled_start_datetime).strftime("%b %-d, %Y")),
          ". Want to add your extra seats now?",
        ]),
        T.nilable(String),
      )
      @color_scheme = T.let(
        (business.renewal_successful? ? :success : :default),
        T.nilable(Symbol),
      )
      @action_text = T.let("Add seats", T.nilable(String))
      @action_url = T.let(billing_add_seats_enterprise_path(business), T.nilable(String))

      return true
    end

    if business.renewal_successful? || business.has_any_pending_change_requests?
      schedule_date = business.renewal_scheduled_start_datetime || business.update_scheduled_start_datetime

      @text = T.let(
        safe_join([
          "Thank you for renewing GitHub Enterprise. Your new contract will start on ",
          content_tag(:strong, T.must(schedule_date).strftime("%b %-d, %Y")),
          ".",
        ]),
        T.nilable(String),
      )
      @color_scheme = T.let(
        (business.renewal_successful? ? :success : :default),
        T.nilable(Symbol),
      )

      return true
    end

    if business.update_successful?
      @text = T.let("Your GitHub Enterprise contract was updated successfully.", T.nilable(String))
      @color_scheme = T.let(:success, T.nilable(Symbol))

      return true
    end

    false
  end
end
