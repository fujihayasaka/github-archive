# typed: true
# frozen_string_literal: true

class SponsorsPayoutExportForm < ApplicationForm
  extend T::Helpers
  extend T::Sig

  form do |f|
    T.bind(self, SponsorsPayoutExportForm)

    f.select_list(name: "payout", label: "Choose a payout", required: true) do |list|
      stripe_payouts.each do |payout|
        list.option(
          label: "#{payout.to_money.format} · #{payout.created_at.strftime("%B %-d, %Y")}",
          value: input_value_for_payout(payout),
        )
      end
    end
    f.submit(name: :submit, label: "Export")
  end

  sig { params(stripe_payouts: T::Array[Billing::Stripe::Payout]).void }
  def initialize(stripe_payouts:)
    @stripe_payouts = stripe_payouts
  end

  private

  sig { returns T::Array[Billing::Stripe::Payout] }
  attr_reader :stripe_payouts

  sig { params(payout: Billing::Stripe::Payout).returns(String) }
  def input_value_for_payout(payout)
    Sponsors::StripePayoutInput.new(account_id: payout.stripe_account_id, payout_id: payout.id).serialize
  end
end
