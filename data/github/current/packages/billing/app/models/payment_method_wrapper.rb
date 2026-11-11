# typed: strict
# frozen_string_literal: true

# PaymentMethodWrapper provides a unified interface for treating both
# regular PaymentMethod objects and azure_subscription_id values as payment methods
# for use with BlocklistedPaymentMethod functionality.
# This class can be deleted once Azure subscription ids are true PaymentMethods
class PaymentMethodWrapper
  sig { params(payment_method: T.nilable(::PaymentMethod), azure_subscription_id: T.nilable(String), customer: T.nilable(Customer)).void }
  def initialize(payment_method: nil, azure_subscription_id: nil, customer: nil)
    if payment_method.nil? && azure_subscription_id.nil?
      raise ArgumentError, "Either payment_method or azure_subscription_id must be provided"
    end

    if payment_method.present? && azure_subscription_id.present?
      raise ArgumentError, "Cannot provide both payment_method and azure_subscription_id"
    end

    @payment_method = payment_method
    @azure_subscription_id = azure_subscription_id
    @customer = customer

    if @azure_subscription_id.present? && @customer.nil?
      # If there's multiple customers associated to the azure subscription id, the first one is selected
      # This is currently only used for blocklisted payment methods, choosing any of the customers is acceptable.
      # However, if functionality of this wrapper is expanded, the customer would have to be a mandatory parameter
      @customer = Customer.with_azure_subscription_id(@azure_subscription_id).first
    end
  end

  # Public: Returns the card fingerprint for this payment method.
  # For regular PaymentMethods, this delegates to the PaymentMethod's card_fingerprint.
  # For azure_subscription_id, the azure_subscription_id itself is the fingerprint.
  sig { returns(T.nilable(String)) }
  def card_fingerprint
    if @payment_method.present?
      @payment_method.card_fingerprint
    else
      @azure_subscription_id
    end
  end

  # Public: Returns the unique_number_identifier.
  # For compatibility with BlacklistedPaymentMethod which expects this field. # rubocop:disable Naming/InclusiveLanguage
  sig { returns(T.nilable(String)) }
  def unique_number_identifier
    @payment_method&.unique_number_identifier
  end

  # Public: Returns the paypal_email.
  # For compatibility with BlacklistedPaymentMethod which expects this field. # rubocop:disable Naming/InclusiveLanguage
  sig { returns(T.nilable(String)) }
  def paypal_email
    if @payment_method.present?
      @payment_method.paypal_email
    else
      nil
    end
  end

  # Public: Returns the owner (User/Organization/Business) for this payment method.
  # For regular PaymentMethods, this delegates to the PaymentMethod's owner.
  # For azure_subscription_id, this returns the Customer's billable_owner.
  sig { returns(T.nilable(Billing::Types::Account)) }
  def owner
    if @payment_method.present?
      @payment_method.owner
    elsif @customer.present?
      @customer.billable_owner
    else
      nil
    end
  end

  # Public: Returns the wrapped PaymentMethod if this wrapper represents a PaymentMethod.
  sig { returns(T.nilable(::PaymentMethod)) }
  def payment_method
    @payment_method
  end

  # Public: Returns the azure_subscription_id if this wrapper represents an azure subscription.
  sig { returns(T.nilable(String)) }
  def azure_subscription_id
    @azure_subscription_id
  end

  sig { returns(T.nilable(Integer)) }
  def payment_method_id
    @payment_method&.id
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def created_at
    @payment_method&.created_at
  end

  sig { returns(String) }
  def payment_processor_type
    @payment_method&.payment_processor_type || "azure"
  end

  sig { returns(T::Boolean) }
  def manually_reviewed?
    @payment_method&.manually_reviewed? || false
  end

  sig { returns(T.nilable(User)) }
  def manually_reviewed_by
    @payment_method&.manually_reviewed_by
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def manually_reviewed_at
    @payment_method&.manually_reviewed_at
  end

  sig { returns(T::Boolean) }
  def blocklisted?
    !!(@payment_method&.blocklisted? || @customer&.azure_subscription_blocklisted?)
  end

  # Public: Returns the customer associated with this payment method.
  sig { returns(T.nilable(Customer)) }
  def customer
    if @payment_method.present?
      @payment_method.customer
    else
      @customer
    end
  end

  # Public: Returns true if this wrapper represents an azure subscription.
  sig { returns(T::Boolean) }
  def azure_subscription?
    @azure_subscription_id.present?
  end

  # Public: Returns true if this wrapper represents a regular PaymentMethod.
  sig { returns(T::Boolean) }
  def payment_method?
    @payment_method.present?
  end

  # Public: Factory method to create a wrapper from a PaymentMethod.
  sig { params(payment_method: ::PaymentMethod).returns(PaymentMethodWrapper) }
  def self.from_payment_method(payment_method)
    new(payment_method: payment_method)
  end

  # Public: Factory method to create a wrapper from an azure_subscription_id.
  sig { params(azure_subscription_id: String, customer: T.nilable(Customer)).returns(PaymentMethodWrapper) }
  def self.from_azure_subscription_id(azure_subscription_id, customer: nil)
    new(azure_subscription_id: azure_subscription_id, customer: customer)
  end

  # Public: Factory method to create a wrapper from a Customer's azure_subscription_id.
  sig { params(customer: Customer).returns(T.nilable(PaymentMethodWrapper)) }
  def self.from_customer_azure_subscription(customer)
    return nil unless customer.azure_subscription_id.present?
    new(azure_subscription_id: customer.azure_subscription_id, customer: customer)
  end
end
