# typed: strict
# frozen_string_literal: true

class Billing::Settings::ConfirmRemovePaymentMethodComponent < ApplicationComponent
  sig { params(target: Billing::Types::Account, return_to: T.nilable(String)).void }
  def initialize(target:, return_to: nil)
    @target = target
    @return_to = return_to
  end

  sig { returns(T::Boolean) }
  def render?
    !target.feature_flag_enabled?(:billing_payment_removal_vnext, default: false)
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(T.nilable(String)) }
  attr_reader :return_to
end
