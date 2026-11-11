# typed: true
# frozen_string_literal: true

# Minimal shim for Stripe types that genuinely differ from the generated RBI.
# v18+ explicitly defines field accessors so most types come from the gem.

class Stripe::StripeObject
  # Not defined on base class but code calls .id on generic StripeObject refs
  sig { returns(String) }
  def id; end
end

# Generated RBI types this as T::Hash[String, T.untyped] but at runtime
# Stripe deserializes into StripeObject subclasses (Charge, Invoice, etc.)
class Stripe::Event::Data < Stripe::StripeObject
  sig { returns(Stripe::StripeObject) }
  def object; end
end

# Connect-specific fields present on API responses but missing from the gem's
# static type definitions.
class Stripe::Transfer < Stripe::APIResource
  sig { returns(T.nilable(Integer)) }
  def destination_amount; end

  sig { returns(T.nilable(String)) }
  def destination_currency; end
end

# amount_due/amount_remaining are typed as Integer in the gem but our code
# passes them through Billing::Types::Numeric interfaces.
class Stripe::Invoice < Stripe::APIResource
  sig { returns(::Billing::Types::Numeric) }
  def amount_due; end

  sig { returns(::Billing::Types::Numeric) }
  def amount_remaining; end
end
