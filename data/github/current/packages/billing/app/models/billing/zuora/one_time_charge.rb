# typed: true
# frozen_string_literal: true

class Billing::Zuora::OneTimeCharge < Billing::Zuora::RatePlanCharge
  include GitHub::Memoizer

  sig { returns(T::Boolean) }
  memoize def active?
    start_date = effective_start_date
    end_date = effective_end_date

    return false if start_date.nil?

    !end_date.nil? && end_date > start_date
  end
end
