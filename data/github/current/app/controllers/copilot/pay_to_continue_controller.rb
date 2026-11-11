# typed: strict
# frozen_string_literal: true

class Copilot::PayToContinueController < Copilot::Signup::BaseController
  include Billing::ManualPaymentRedirect

  # How long a rendered checkout price stays locked. We re-lock on every checkout render
  # and delete on a successful charge, so this is really just a backstop that garbage-
  # collects abandoned locks. It's long enough that a normal render-then-pay flow never
  # expires; if it ever does, `create` re-confirms rather than charging an unshown price.
  PRICE_LOCK_TTL = T.let(1.day, ActiveSupport::Duration)

  before_action :login_required
  before_action :restrict_emu_access
  before_action :check_feature_flag_enabled
  before_action :check_consumptive_user
  before_action :ensure_spending_info_available

  before_action only: [:new] do
    T.bind(self, Copilot::PayToContinueController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:create] do
    T.bind(self, Copilot::PayToContinueController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  javascript_bundle :billing, only: [:new]
  global_navigation_title "Pay to continue checkout", only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:new]

  sig { void }
  def new
    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_PAY_TO_CONTINUE_PAGE_VIEW,
      copilot_user
    )

    render "copilot/pay_to_continue/new", locals: {
      copilot_user: copilot_user,
      amount_to_pay: lock_price!,
      submit_path: copilot_pay_to_continue_create_path,
      return_to: return_to,
    }, formats: :html
  end

  sig { void }
  def create
    billing_customer = customer
    usage_product = product_uuid

    if billing_customer.nil? || usage_product.nil?
      flash[:error] = "We couldn't process your payment. Please try again."
      safe_redirect_to(return_to, fallback: copilot_features_path)
      return
    end

    # Only charge if the price the customer saw on the page they just submitted still
    # matches the amount we locked server-side. If the lock is gone (expired/corrupt) or
    # the submitted quote doesn't match it (a stale tab, or the lock was refreshed since
    # this page rendered), we no longer know they agreed to this amount, so re-render
    # checkout with a fresh quote instead of charging something they never confirmed. The
    # submitted value is only ever a cross-check; the charge always uses the locked amount.
    # The manual-payment re-POST is exempt: it reuses the original idempotency key to
    # finalize an already-authorized charge.
    locked = locked_amount
    unless quote_matches_lock?(locked) || manual_payment_finalization?
      flash[:notice] = "Your total was updated. Please review and pay to continue."
      redirect_to copilot_pay_to_continue_path(return_to: return_to)
      return
    end

    orchestrator = ::Billing::PayAsYouGoOrchestrator.new(
      customer: billing_customer,
      amount_to_pay: locked || amount_to_pay,
      product_uuid: usage_product,
      idempotency_key: params[:idempotency_key].presence,
    )
    result = orchestrator.call

    if result.ok?
      clear_price_lock
      flash[:notice] = "You've successfully paid your additional usage."
      safe_redirect_to(return_to, fallback: copilot_features_path)
      return
    end

    # This is the re-POST from the manual payments page. If we can confirm the manual payment was
    # actually collected, send them back to retry once it settles (showing the payment-processing
    # banner) instead of looping them to the payment page. If we can't confirm it went through, fall
    # through so they're redirected back to complete payment rather than being reassured prematurely.
    if manual_payment_finalization? && result.error.is_a?(::Billing::ManualPaymentRequiredError) &&
        manual_payment_collected?(target: current_user, invoice_id: result.error.invoice_id)
      redirect_to copilot_pay_to_continue_path(
        :return_to => return_to,
        Billing::ManualPaymentRedirect::PAYMENT_PROCESSING_PARAM => true,
      )
      return
    end

    # The advance payment may have been declined because the customer must pay manually (India RBI).
    # Send them to the manual payments page to authorize the pending invoice. We stash a pending
    # payment so that, once they pay, the page re-POSTs here reusing the same idempotency key. That
    # re-runs the orchestrator, which finds the now-settled invoice and emits the charge-collected
    # event that resets their usage cap (paying the invoice alone doesn't reset it).
    if result.error.is_a?(::Billing::ManualPaymentRequiredError)
      pending_payment = Billing::PendingManualPaymentUpgrade.new(
        path: copilot_pay_to_continue_create_path,
        params: {
          "return_to" => return_to,
          "return_to_path" => copilot_pay_to_continue_path(return_to: return_to),
          "idempotency_key" => orchestrator.idempotency_key,
        },
      )
      return if redirect_to_manual_payment_if_required(result.error, target: current_user, pending_upgrade: pending_payment, require_pending_upgrade: false)
    end

    flash[:error] = result.error.to_s.presence || "We couldn't process your payment. Please try again."
    safe_redirect_to(return_to, fallback: copilot_features_path)
  end

  private

  sig { returns(Copilot::User) }
  memoize def copilot_user
    Copilot::User.new(current_user)
  end

  sig { returns(String) }
  def return_to
    params[:return_to].presence || request.referrer.presence || copilot_features_path
  end

  sig { void }
  def ensure_spending_info_available
    return if spending_info

    flash[:error] = "We couldn't load your additional usage details. Please try again."
    safe_redirect_to(return_to, fallback: copilot_features_path)
  end

  sig { returns(T.nilable(Copilot::QuotaDataHelper::SpendingInfo)) }
  memoize def spending_info
    Copilot::QuotaDataHelper.fetch_copilot_spending_info(
      client: ::Billing::Platform::Api::Client.new,
      copilot_user: copilot_user,
    )
  end

  sig { returns(Billing::Money) }
  def amount_to_pay
    info = spending_info
    cents = info ? (info[:overage_amount] * 100).round : 0
    Billing::Money.new(cents)
  end

  # Snapshots the current overage as the locked checkout price and returns it. Called
  # when rendering the checkout page so the amount we show is the amount we'll charge.
  # KV writes have to run on the writing connection.
  sig { returns(Billing::Money) }
  def lock_price!
    amount = amount_to_pay
    ActiveRecord::Base.connected_to(role: :writing) do
      Copilot::KV.store.set(price_lock_key, amount.cents.to_s, expires: PRICE_LOCK_TTL.from_now)
    end
    amount
  end

  # The price we locked in when checkout rendered. Returns nil when there's no usable lock
  # (missing, expired, or corrupt), so callers re-confirm rather than charge an amount the
  # customer never saw. The value is never read from request params, so it can't be
  # tampered with the way a hidden form field could.
  sig { returns(T.nilable(Billing::Money)) }
  def locked_amount
    raw = Copilot::KV.store.get(price_lock_key).value { nil }
    return unless raw
    return unless raw.match?(/\A\d+\z/)

    cents = raw.to_i
    return unless cents.positive?

    Billing::Money.new(cents)
  end

  # True when the price the customer submitted from the checkout page matches the amount we
  # locked server-side. The submitted value is a tamper-check only, never the charge basis.
  sig { params(locked: T.nilable(Billing::Money)).returns(T::Boolean) }
  def quote_matches_lock?(locked)
    submitted = quoted_amount_cents
    !locked.nil? && !submitted.nil? && locked.cents == submitted
  end

  sig { returns(T.nilable(Integer)) }
  def quoted_amount_cents
    raw = params[:quoted_amount_cents]
    return unless raw.is_a?(String) && raw.match?(/\A\d+\z/)

    raw.to_i
  end

  # KV writes have to run on the writing connection.
  sig { void }
  def clear_price_lock
    ActiveRecord::Base.connected_to(role: :writing) do
      Copilot::KV.store.del(price_lock_key)
    end
  end

  sig { returns(String) }
  def price_lock_key
    "copilot.pay_to_continue.charge_cents.#{current_user.id}"
  end

  sig { returns(T.nilable(::Customer)) }
  memoize def customer
    current_user.customer
  end

  sig { returns(T.nilable(::Billing::ProductUUID)) }
  memoize def product_uuid
    ::Billing::ProductUUID
      .copilot
      .metered
      .with_product_key("GitHub Copilot Usage")
      .first
  end

  sig { void }
  def check_feature_flag_enabled
    return if FeatureFlag.vexi.enabled?(:copilot_cfi_pay_to_continue, current_user, default: false)
    render_404
  end

  sig { void }
  def check_consumptive_user
    return if copilot_user.consumptive_user?
    render_404
  end
end
