# typed: strict
# frozen_string_literal: true

class Billing::Stripe::Webhooks::EarlyFraudWarning
  include GitHub::Memoizer

  sig { returns(::Stripe::Event) }
  attr_reader :event
  sig { returns(Billing::StripeWebhook) }
  attr_reader :webhook

  HYDRO_FRAUD_TYPES = T.let([
    :CARD_NEVER_RECEIVED,
    :FRAUDULENT_CARD_APPLICATION,
    :MADE_WITH_COUNTERFEIT_CARD,
    :MADE_WITH_LOST_CARD,
    :MADE_WITH_STOLEN_CARD,
    :MISC,
    :UNAUTHORIZED_USE_OF_CARD
  ].freeze, T::Array[Symbol])

  # Public: Handle the early fraud warning webhook payload
  sig { params(webhook: Billing::StripeWebhook).void }
  def self.perform(webhook)
    new(webhook).perform
  end

  # Public: Initializes a new EarlyFraudWarning webhook handler
  sig { params(webhook: Billing::StripeWebhook).void }
  def initialize(webhook)
    @webhook = webhook
    @event = T.let(webhook.stripe_event, ::Stripe::Event)
    @early_fraud_warning = T.let(T.cast(@event.data.object, ::Stripe::Radar::EarlyFraudWarning), ::Stripe::Radar::EarlyFraudWarning)
  end

  # Public: Handle the early fraud warning webhook payload
  sig { void }
  def perform
    return unless live_mode?
    instrument_early_fraud_warning
    Sponsors::EmitEarlyFraudWarning.call(early_fraud_warning_event)
  end

  private

  sig { returns(::Stripe::Radar::EarlyFraudWarning) }
  attr_reader :early_fraud_warning

  sig { returns(T::Boolean) }
  def live_mode?
    !!early_fraud_warning.livemode
  end

  sig { void }
  def instrument_early_fraud_warning
    GlobalInstrumenter.instrument("billing.early_fraud_warning",
      **early_fraud_warning_event
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def early_fraud_warning_event
    {
      stripe_fraud_id: early_fraud_warning.id,
      actionable: early_fraud_warning.actionable,
      stripe_charge_id: early_fraud_warning.charge,
      stripe_timestamp: Time.at(early_fraud_warning.created).to_datetime,
      fraud_type: hydro_fraud_type,
      user_id: early_fraud_warning_transaction.user_id,
    }.freeze
  end

  # Raises ActiveRecord::RecordNotFound
  sig { returns(Billing::BillingTransaction) }
  memoize def early_fraud_warning_transaction
    Billing::BillingTransaction.find_by!(
      transaction_id: early_fraud_warning.charge,
    )
  end

  sig { returns(Symbol) }
  def hydro_fraud_type
    normalized_value = early_fraud_warning.fraud_type.upcase.to_sym
    return normalized_value if HYDRO_FRAUD_TYPES.include?(normalized_value)
    :UNKNOWN
  end
end
