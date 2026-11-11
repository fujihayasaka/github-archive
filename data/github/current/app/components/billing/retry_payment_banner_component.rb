# typed: strict
# frozen_string_literal: true

class Billing::RetryPaymentBannerComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  include GitHub::Memoizer

  MAX_RETRY_ATTEMPTS = ::User::BillingDependency::BILLING_ATTEMPTS_LIMIT

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  sig { params(account: Billing::Types::Account, current_user: T.nilable(User)).void }
  def initialize(account:, current_user:)
    @current_user = current_user
    @account = account
    @customer = T.let(account.customer, T.nilable(Customer))
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :account

  sig { returns(T.nilable(User)) }
  attr_reader :current_user

  sig { returns(T.nilable(Customer)) }
  attr_reader :customer

  sig { returns(String) }
  def path_to_payment_page
    if account.business?
      enterprise_billing_payment_information_path(account)
    elsif account.organization?
      settings_org_billing_tab_path(account, tab: "payment_information")
    else
      settings_user_billing_tab_path(tab: "payment_information")
    end
  end

  # The state of the payment retry process
  sig { returns(Symbol) }
  memoize def payment_state
    return :none if customer.nil?
    job_status = Billing::RetryFailedPaymentJob.status(T.must(customer))
    return :success if job_status&.success?
    return :retrying if job_status && !job_status.finished?
    return :failed if payment_failed?
    :none
  end

  # Check if payment failed
  sig { returns(T::Boolean) }
  memoize def payment_failed?
    account.dunning? && !account.disabled?
  end

  # Get the failure reason for the most recent failed payment
  sig { returns(T.nilable(Symbol)) }
  memoize def failure_reason
    return nil unless payment_failed?
    return :card_expired if card_expired?

    latest_transaction = account.billing_transactions
      .unsuccessful_payment_collection
      .descending
      .first
    return nil unless latest_transaction

    gateway_response = zuora_payment(transaction_id: latest_transaction.platform_transaction_id)&.gateway_response
    if gateway_response&.include?("insufficient_funds")
      return :insufficient_funds
    elsif gateway_response&.include?("expired_card")
      return :card_expired
    end

    :generic_decline
  end

  sig { params(transaction_id: String).returns(T.nilable(Billing::Zuora::Payment)) }
  def zuora_payment(transaction_id:)
    payment = begin
      Billing::Zuora::Payment.find(transaction_id)
    rescue Zuorest::HttpError, Zuorest::TooManyRequestsError, Zuorest::GatewayTimeoutError
      nil
    end
  end

  sig { returns(Integer) }
  memoize def attempt_number
    account.billing_attempts + 1
  end

  sig { returns(T::Boolean) }
  def card_expired?
    return false unless account.has_credit_card?

    today = GitHub::Billing.today
    payment_method = account.payment_method
    return false unless payment_method

    expiration_year = payment_method.expiration_year
    expiration_month = payment_method.expiration_month
    return false unless expiration_year && expiration_month

    expiration_year < today.year || (
      expiration_year == today.year &&
      expiration_month < today.month
    )
  end

  sig { returns(String) }
  def banner_title
    case payment_state
    when :success
      "Payment successful"
    when :retrying
      "Retrying your payment..."
    when :failed
      case failure_reason
      when :card_expired
        "Your card has expired"
      when :insufficient_funds
        "Payment failed due to insufficient funds"
      when :bank_blocked
        "Your bank blocked the payment"
      else
        "We couldn't process your payment (Attempt #{attempt_number} of #{MAX_RETRY_ATTEMPTS})"
      end
    else
      ""
    end
  end

  sig { returns(String) }
  def banner_message
    case payment_state
    when :success
      "Your payment went through—you're all set."
    when :retrying
      "We're working to process your payment. This may take a few minutes. You'll see an update here when it's complete."
    when :failed
      case failure_reason
      when :card_expired
        "Your payment couldn't be processed because your card has expired. Please update your payment method to continue service."
      when :insufficient_funds
        "Your payment couldn't be processed because there aren't enough funds on your card. Add funds or use a different card, then try again to continue service."
      when :bank_blocked
        "Your payment was declined by your bank. Please contact your bank to resolve the issue, or update your payment method to continue service."
      else
        "This is usually because your card expired, there aren't enough funds, or your bank blocked the payment. Retry the payment once resolved, or update your payment method or contact your bank to continue your service."
      end
    else
      ""
    end
  end

  sig { returns(Symbol) }
  def banner_scheme
    case payment_state
    when :success
      :default
    when :retrying
      :warning
    when :failed
      :warning
    else
      :default
    end
  end

  sig { returns(Symbol) }
  def banner_icon
    return :info if payment_state == :success
    :alert
  end

  sig { returns(T::Boolean) }
  def dismissable?
    [:success, :retrying].include?(payment_state)
  end

  sig { returns(T::Boolean) }
  def show_retry_button?
    return false unless customer&.payment_method&.valid_payment_token?
    return false if account.billing_attempts.to_i >= MAX_RETRY_ATTEMPTS
    payment_state == :failed && failure_reason != :card_expired
  end

  sig { returns(T::Boolean) }
  def show_update_button?
    payment_state == :failed
  end

  sig { returns(String) }
  def learn_more_url
    "https://docs.github.com/en/billing/how-tos/set-up-payment/manage-payment-info"
  end

  private

  sig { returns(T::Boolean) }
  def has_permission_to_view_banner?
    if account.is_a?(Business) || account.is_a?(Organization)
      account.adminable_by?(current_user) || T.unsafe(account).billing_manager?(current_user)
    else
      account.adminable_by?(current_user)
    end
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless logged_in?
    return false unless customer
    return false unless has_permission_to_view_banner?
    return false if account.invoiced?
    return false if account.delegate_billing_to_business?
    return false if T.must(customer).auto_pay_reasons&.any?
    return false if T.must(customer).payment_method_verification_in_progress?

    # Only display banner if there's a relevant payment state to show
    payment_state != :none
  end
end
