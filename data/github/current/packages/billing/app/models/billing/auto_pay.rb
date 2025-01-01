# typed: strict
# frozen_string_literal: true

class Billing::AutoPay
  extend T::Sig

  sig do
    params(account: Billing::Types::Account, reason: T.any(Symbol, String), actor: T.nilable(User))
      .returns(T.nilable(GitHub::Billing::Result))
  end
  def self.enable!(account:, reason:, actor: nil); new(account: account, reason: reason, actor: actor).enable!; end
  sig do
    params(account: Billing::Types::Account, reason: T.any(Symbol, String), actor: T.nilable(User))
      .returns(T.nilable(GitHub::Billing::Result))
  end
  def self.disable!(account:, reason:, actor: nil); new(account: account, reason: reason, actor: actor).disable!; end

  sig do
    params(account: Billing::Types::Account, reason: T.any(Symbol, String), actor: T.nilable(User))
      .void
  end
  def initialize(account:, reason:, actor: nil)
    @account = account
    @actor = actor
    @reason = T.let(reason.to_sym, Symbol)
  end

  # Enable auto-pay for an account
  sig { returns(T.nilable(GitHub::Billing::Result)) }
  def enable!
    return unless customer&.zuora?
    return if !customer.auto_pay_reasons.empty? && !customer.auto_pay_reasons.include?(reason)

    customer.update auto_pay_reasons: customer.auto_pay_reasons.delete(reason)
    instrument_reason_remove

    if (customer.auto_pay_reasons - Customer::AUTO_PAY_DISABLE_REASONS_ALLOWED_FOR_ENABLE).empty?
      result = change_status(true)
    end

    result
  end

  # Disable auto-pay for an account
  #
  # Returns Billing::Result if update attempted, otherwise nil.
  # Raises ArgumentError if reason is invalid.
  sig { returns(T.nilable(GitHub::Billing::Result)) }
  def disable!
    return unless customer&.zuora?

    unless Customer::AUTO_PAY_DISABLE_REASONS.has_key?(reason)
      raise ArgumentError, "#{reason} is not a valid option for disabling auto pay."
    end

    # we only want o skip disabling if the reason is already in auto_pay_reasons and auto pay is already disabled
    return if customer.auto_pay_reasons.include?(reason) && !customer.auto_pay?

    customer.update auto_pay_reasons: customer.auto_pay_reasons.add(reason)
    instrument_reason_add
    change_status false
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :account
  sig { returns(T.nilable(User)) }
  attr_reader :actor
  sig { returns(Symbol) }
  attr_reader :reason

  delegate :customer, to: :account
  delegate :zuora_account, to: :customer

  sig { params(status: T::Boolean).void }
  def instrument_change(status:)
    payload = {
      actor: actor,
      auto_pay_status: status,
      auto_pay_reason: reason
    }

    if account.is_a?(Business)
      payload[:business] = account
    elsif account.organization?
      payload[:org] = account
    else
      payload[:user] = account
    end

    GitHub.instrument "account.toggle_auto_pay", payload
    GitHub.dogstats.increment "account.toggle_auto_pay",
      tags: ["status:#{status}", "reason:#{reason}"]
  end

  sig { void }
  def instrument_reason_add
    GitHub.dogstats.increment "account.auto_pay_reason",
      tags: ["type:add", "reason:#{reason}", "empty_reasons:false"]
  end

  sig { void }
  def instrument_reason_remove
    GitHub.dogstats.increment "account.auto_pay_reason",
      tags: ["type:remove", "reason:#{reason}", "empty_reasons:#{customer.auto_pay_reasons.empty?}"]
  end

  sig { params(status: T::Boolean).returns(GitHub::Billing::Result) }
  def change_status(status)
    # return success if we're trying to enable auto pay but it's already enabled
    return GitHub::Billing::Result.success if status && customer.auto_pay?
    # return success if we're trying to disable auto pay but it's already disabled
    return GitHub::Billing::Result.success if !status && !customer.auto_pay?

    response = zuora_account.update! AutoPay: status
    result = GitHub::Billing::Result.from_zuora(response.first)
    instrument_change(status: status) if result&.success?

    result
  end
end
