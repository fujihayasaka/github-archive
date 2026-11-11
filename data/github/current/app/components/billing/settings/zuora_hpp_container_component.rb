# typed: true
# frozen_string_literal: true

class Billing::Settings::ZuoraHppContainerComponent < ApplicationComponent
  # signature_path - String URL
  # user_id - optional Integer database ID for the currently authenticated User
  # organization_id - optional String Organization login
  # business_id - optional String Business slug
  # target - optional String identifying the target type, e.g., "organization"
  # signature_view_context - optional String
  # hidden - optional Boolean, defaults to not being hidden
  # manual_payment - optional Boolean, defaults to not being a manual payment
  # invoices - optional Array of Zuora invoice number Strings (e.g. ["INV0001", "INV0002"])
  # payment_gateway - optional String Zuora payment gateway name (e.g. "Sponsors Stripe v2")
  # ignore_default_classes - optional Boolean to omit default CSS classes from the containing div element; defaults to
  #                          including those default classes
  # terms_of_service - optional String descriptor of the terms of service that apply, e.g., "standard"
  # container_class - optional String of additional CSS classes to apply to the containing div element
  # redirect_to - optional String URL to redirect the user to afterward
  # hydro_payload - optional Hash of Hydro analytics attributes to include in the
  #                 'payment_method.verification_failure' event
  def initialize(signature_path:, user_id: nil, organization_id: nil, business_id: nil, target: nil, signature_view_context: nil, manual_payment: false, invoices: nil, payment_gateway: nil, ignore_default_classes: false, terms_of_service: nil, container_class: nil, hidden: false, redirect_to: nil, hydro_payload: {})
    @signature_path = signature_path
    @user_id = user_id
    @organization_id = organization_id
    @business_id = business_id
    @target = target
    @signature_view_context = signature_view_context
    @manual_payment = manual_payment
    @invoices = invoices
    @payment_gateway = payment_gateway
    @ignore_default_classes = ignore_default_classes
    @terms_of_service = terms_of_service
    @container_class = container_class
    @hidden = hidden
    @redirect_to = redirect_to
    @hydro_payload = hydro_payload
  end

  private

  attr_reader :user_id, :organization_id, :business_id, :target, :signature_view_context, :signature_path,
    :terms_of_service, :container_class, :redirect_to, :hydro_payload, :invoices, :payment_gateway

  def render?
    signature_path.present?
  end

  def ignore_default_classes?
    @ignore_default_classes
  end

  def hidden?
    @hidden
  end

  def manual_payment?
    @manual_payment
  end

  def div_class
    if ignore_default_classes?
      container_class.presence
    else
      class_names("ml-n3 mr-n3", container_class)
    end
  end

  def encoded_hydro_payload
    encode_hydro_payload("payment_method.verification_failure", hydro_payload)
  end
end
