# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Payouts::ListComponent < ApplicationComponent
  def initialize(stripe_account:, limit:)
    @stripe_account = stripe_account
    @limit          = limit
  end

  private

  attr_reader :stripe_account, :limit

  def render?
    stripe_account.present? && limit.present?
  end

  memoize def payouts_response
    stripe_account.stripe_payouts(limit: limit)
  end

  memoize def payouts
    payouts_response.result
  end

  def empty_results?
    payouts.blank?
  end

  def failed?
    !payouts_response.success?
  end
end
