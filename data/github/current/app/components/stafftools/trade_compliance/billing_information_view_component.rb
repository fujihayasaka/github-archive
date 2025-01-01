# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::BillingInformationViewComponent < ApplicationComponent
  include StafftoolsHelper

  sig { params(target: Billing::Types::Account, show_billing_info: T::Boolean).void }
  def initialize(target:, show_billing_info: false)
    @target = target
    @show_billing_info = show_billing_info
  end

  sig { returns(Billing::Types::BillingInformation) }
  def billing_contact
    target.billing_contact
  end

  sig { returns(T::Boolean) }
  def render_info?
    show_billing_info && allowed_to_view_billing_info?
  end

  sig { returns(String) }
  def button_text
    verb = if show_billing_info
      "Hide"
    else
      "Show"
    end

    "#{verb} Billing Information"
  end

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = if target.is_a?(Business)
      Stafftools::Businesses::TradeComplianceController
    else
      Stafftools::Users::TradeComplianceController
    end

    stafftools_action_authorized?(controller: controller, action: :create)
  end

  sig { returns(String) }
  def controller_path
    return stafftools_user_trade_compliance_path(target) unless target.is_a?(Business)

    stafftools_enterprise_trade_compliance_path(target)
  end

  sig { returns(Symbol) }
  def action
    if show_billing_info
      :get
    else
      :post
    end
  end

  sig { returns(String) }
  memoize def description
    return "" if allowed_to_view_billing_info?
    return "This account doesn't have any billing information." unless billing_contact.persisted?

    "This account only has internally created billing information."
  end

  sig { returns(T::Boolean) }
  memoize def organization_with_a_linked_record?
    return false unless target.org_is_on_standard_tos?
    T.cast(target, Organization).has_linked_billing_contact?
  end

  sig { returns(T.nilable(String)) }
  def first_name
    billing_contact.first_name
  end

  sig { returns(T.nilable(String)) }
  def last_name
    billing_contact.last_name
  end

  sig { returns(String) }
  def address1
    billing_contact.address1
  end

  sig { returns(T.nilable(String)) }
  def address2
    billing_contact.address2
  end

  sig { returns(String) }
  def city
    billing_contact.city
  end

  sig { returns(String) }
  def country
    billing_contact.country_code
  end

  sig { returns(T.nilable(String)) }
  def region
    billing_contact.region
  end

  sig { returns(T.nilable(String)) }
  def postal_code
    billing_contact.postal_code
  end

  sig { returns(T.nilable(String)) }
  def entity_name
    billing_contact.entity_name
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def updated_at
    billing_contact.updated_at
  end

  sig { returns(T::Boolean) }
  def user_owned?
    entity_name.blank?
  end

  sig { returns(T.nilable(String)) }
  def linked_admin_path
    return nil unless organization_with_a_linked_record?
    stafftools_user_trade_compliance_path(T.cast(target, ::Organization).trade_screening_record.user)
  end

  private

  sig { returns(T::Boolean) }
  memoize def allowed_to_view_billing_info?
    return false unless billing_contact.persisted?
    !organization_with_a_linked_record?
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(T::Boolean) }
  attr_reader :show_billing_info
end
