# typed: strict
# frozen_string_literal: true

class SponsorsListing
  sig { params(billing_cycle: T.any(String, Symbol)).returns(T.nilable(Billing::ProductUUID)) }
  def product_uuid(billing_cycle); end

  sig { params(banned_reason: String, automated: T::Boolean).void }
  def ban!(banned_reason:, automated: false); end
end
