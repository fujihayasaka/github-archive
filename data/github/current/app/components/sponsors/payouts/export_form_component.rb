# typed: strict
# frozen_string_literal: true

class Sponsors::Payouts::ExportFormComponent < ApplicationComponent
  # sponsorable_login - the login of maintainer who owns the payouts
  # form_url - the URL path for the export form action
  # stripe_payouts - list of payouts to render
  # success - whether to show an error or not
  sig do
    params(
      sponsorable_login: String,
      form_url: String,
      stripe_payouts: T::Array[Billing::Stripe::Payout],
      success: T::Boolean,
    ).void
  end
  def initialize(
    sponsorable_login:,
    form_url:,
    stripe_payouts: [],
    success: true
  )
    @sponsorable_login = sponsorable_login
    @form_url = form_url
    @stripe_payouts = stripe_payouts
    @success = success
  end

  private

  sig { returns String }
  attr_reader :sponsorable_login

  sig { returns String }
  attr_reader :form_url

  sig { returns T::Array[Billing::Stripe::Payout] }
  attr_reader :stripe_payouts

  sig { returns T::Boolean }
  def error?
    !@success
  end
end
