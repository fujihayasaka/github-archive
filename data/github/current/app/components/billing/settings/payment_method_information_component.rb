# typed: strict
# frozen_string_literal: true

class Billing::Settings::PaymentMethodInformationComponent < ApplicationComponent
  sig { returns(Billing::Types::Account) }
  attr_reader :target


  sig { params(target: Billing::Types::Account).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def has_unpaid_invoices?
    target.balance.positive?
  end
end
