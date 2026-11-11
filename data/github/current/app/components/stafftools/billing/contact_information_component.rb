# typed: strict
# frozen_string_literal: true

# Component for displaying billing and shipping contact information in stafftools
# This component provides a unified interface for both billing and shipping contact
# display and editing functionality with proper authorization checks.
#
# @example Rendering billing information for a user (hidden by default)
#   Stafftools::Billing::ContactInformationComponent.new(customer: user.billable_owner.customer, contact_type: :billing)
#
# @example Rendering billing information for a user (visible)
#   Stafftools::Billing::ContactInformationComponent.new(customer: user.billable_owner.customer, contact_type: :billing, show_info: true)
#
# @example Rendering shipping information for an enterprise
#   Stafftools::Billing::ContactInformationComponent.new(customer: business.billable_owner.customer, contact_type: :shipping, show_info: true)
class Stafftools::Billing::ContactInformationComponent < ApplicationComponent
  include StafftoolsHelper

  VALID_CONTACT_TYPES = T.let([:billing, :shipping].freeze, T::Array[Symbol])

  # Parameter names for show/hide functionality
  SHOW_PARAM_NAMES = T.let({
    billing: "show_billing_info",
    shipping: "show_shipping_info"
  }.freeze, T::Hash[Symbol, String])

  # Display titles for each contact type
  CONTACT_TITLES = T.let({
    billing: "Billing Information",
    shipping: "Shipping Information"
  }.freeze, T::Hash[Symbol, String])

  sig { returns(T.nilable(Customer)) }
  attr_reader :customer

  sig { returns(Symbol) }
  attr_reader :contact_type

  delegate :first_name, :last_name, :address1, :address2, :city, :country_code, :region, :postal_code, :entity_name, :updated_at, to: :contact, allow_nil: true

  sig { params(customer: T.nilable(Customer), contact_type: Symbol, show_info: T::Boolean).void }
  def initialize(customer:, contact_type:, show_info: false)
    @customer = customer
    @show_info = show_info
    @contact_type = contact_type
    validate_contact_type!
  end

  sig { returns(T.nilable(Billing::Contact)) }
  memoize def contact
    return nil unless customer

    contact_result = case contact_type
    when :billing
      T.must(customer).billing_contact
    when :shipping
      T.must(customer).shipping_contact
    end

    # Filter to only return Billing::Contact, not AccountScreeningProfile
    contact_result.is_a?(Billing::Contact) ? contact_result : nil
  end

  sig { returns(String) }
  def contact_title
    CONTACT_TITLES[contact_type] || "Contact Information"
  end

  sig { returns(String) }
  def show_param_name
    SHOW_PARAM_NAMES[contact_type] || "show_info"
  end

  sig { returns(String) }
  def data_test_selector
    "#{contact_type}-information-data"
  end

  sig { returns(T::Boolean) }
  def render_info?
    show_info && allowed_to_view_contact_info? && authorized_staffer?
  end

  sig { returns(String) }
  def button_text
    verb = show_info ? "Hide" : "Show"
    "#{verb} #{contact_title}"
  end

  sig { returns(T::Boolean) }
  def authorized_staffer?
    return false unless billable_owner

    controller = case billable_owner
    when User # This includes Organization since it inherits from User
      Stafftools::Users::Billing::InformationController
    when Business
      Stafftools::Businesses::Billing::InformationController
    end

    stafftools_action_authorized?(controller: controller, action: :index)
  end

  sig { returns(T.nilable(String)) }
  def controller_path
    return nil unless billable_owner

    case billable_owner
    when User # This includes Organization since it inherits from User
      Rails.application.routes.url_helpers.stafftools_user_billing_information_index_path(billable_owner)
    when Business
      Rails.application.routes.url_helpers.stafftools_enterprise_billing_information_index_path(billable_owner)
    end
  end

  sig { returns(String) }
  def description
    return "" if allowed_to_view_contact_info?
    "This account doesn't have any #{contact_type} information."
  end

  sig { returns(T::Boolean) }
  def user_owned?
    entity_name.blank?
  end

  private

  sig { returns(T::Boolean) }
  attr_reader :show_info

  sig { returns(T.nilable(T.any(User, Business))) }
  def billable_owner
    customer&.billable_owner
  end

  sig { returns(T::Boolean) }
  def allowed_to_view_contact_info?
    contact&.persisted?
  end

  sig { void }
  def validate_contact_type!
    unless VALID_CONTACT_TYPES.include?(contact_type)
      raise ArgumentError, "Invalid contact_type: #{contact_type}. Must be one of: #{VALID_CONTACT_TYPES.join(', ')}"
    end
  end
end
