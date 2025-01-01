# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PaymentGateway
  extend T::Sig
  # List of Gateways created in Zuora
  # - Stripe v2 (to be used for 3DS support)
  # - Paypal
  # The names of the gateways correspond to the assigned names in Zuora's settings
  STRIPE_V1 = "Stripe"
  STRIPE_V2 = "Stripe v2"
  STRIPE_V3 = "Stripe v3"
  SPONSORS_STRIPE_V2 = "Sponsors Stripe v2"
  STRIPE_GATEWAYS = T.let([STRIPE_V1, STRIPE_V2, STRIPE_V3, SPONSORS_STRIPE_V2].freeze, T::Array[String])
  PAYPAL = "Paypal"

  # Public: Returns the name of the gateway to use for the given user and type of payment
  #
  # user - User to check gateway eligibility
  # type - Symbol either `credit_card` or `paypal` used to determine gateway
  # purpose - Symbol indicating what kind of purchase this payment gateway will be used for; choose from :general
  #           or :sponsors
  #
  sig { params(user: T.nilable(T.any(::Billing::Types::Account, Billing::DeadUser)), type: T.nilable(Symbol), purpose: T.nilable(Symbol)).returns(String) }
  def self.for(user, type:, purpose: Customer::DEFAULT_PURPOSE)
    new(user, type: type, purpose: purpose).name
  end

  sig { params(user: T.nilable(T.any(::Billing::Types::Account, Billing::DeadUser)), type: T.nilable(Symbol), purpose: T.nilable(Symbol)).void }
  def initialize(user, type: nil, purpose: Customer::DEFAULT_PURPOSE)
    validate_type(type)
    validate_purpose(purpose)

    @user = user
    @type = type
    @purpose = purpose
  end

  # Public: Validates and assigns the type for the gateway determination
  #
  # type - Symbol either `credit_card` or `paypal` used to determine gateway
  sig { params(type: T.nilable(Symbol)).returns(T.nilable(Symbol)) }
  def type=(type)
    validate_type(type)

    @type = type
  end

  # Public: Returns the name of the gateway to use for the given user and type of payment
  sig { returns(String) }
  def name
    raise RuntimeError, "type needs to be present to resolve gateway name" unless type.present?

    if credit_card?
      if sponsors_purpose?
        SPONSORS_STRIPE_V2
      else
        STRIPE_V3
      end
    else
      PAYPAL
    end
  end

  sig { returns(T::Boolean) }
  def paypal?
    name == PAYPAL
  end

  sig { returns(T::Boolean) }
  def credit_card?
    type == :credit_card
  end

  private

  sig { returns(T.nilable(Symbol)) }
  attr_reader :type
  sig { returns(T.nilable(T.any(::Billing::Types::Account, ::Billing::DeadUser))) }
  attr_reader :user
  sig { returns(T.nilable(Symbol)) }
  attr_reader :purpose

  sig { returns(T::Boolean) }
  def sponsors_purpose?
    purpose == :sponsors
  end

  sig { params(type: T.nilable(Symbol)).void }
  def validate_type(type)
    raise ArgumentError, "Invalid gateway type #{type}" if type && !type.in?([:credit_card, :paypal])
  end

  sig { params(purpose: T.nilable(Symbol)).void }
  def validate_purpose(purpose)
    allowed_purposes = [:general, :sponsors]
    if purpose && !purpose.in?(allowed_purposes)
      allowed_summary = allowed_purposes.map(&:inspect).join(", ")
      raise ArgumentError, "Invalid gateway purpose #{purpose.inspect}, expected one of #{allowed_summary}"
    end
  end
end
