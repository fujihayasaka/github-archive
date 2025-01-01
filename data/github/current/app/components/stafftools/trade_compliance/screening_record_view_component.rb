# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::ScreeningRecordViewComponent < ApplicationComponent
  include StafftoolsHelper
  extend T::Sig

  sig { params(target: Billing::Types::Account, show_billing_info: T::Boolean).void }
  def initialize(target:, show_billing_info: false)
    @target = target
    @show_billing_info = show_billing_info
    @trade_screening_record = T.let(target.trade_screening_record(ignore_linked_record: true), AccountScreeningProfile)
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
    return "This account doesn't have any billing information." unless trade_screening_record.persisted?

    "This account only has internally created billing information."
  end

  sig { returns(T::Boolean) }
  memoize def has_saved_trade_screening_record?
    target.has_saved_trade_screening_record?
  end

  sig { returns(T::Boolean) }
  memoize def organization_with_a_linked_record?
    target.has_linked_trade_screening_record?
  end

  sig { returns(T.nilable(String)) }
  def first_name
    trade_screening_record.first_name
  end

  sig { returns(T.nilable(String)) }
  def last_name
    trade_screening_record.last_name
  end

  sig { returns(String) }
  def address1
    trade_screening_record.address1
  end

  sig { returns(T.nilable(String)) }
  def address2
    trade_screening_record.address2
  end

  sig { returns(String) }
  def city
    trade_screening_record.city
  end

  sig { returns(String) }
  def country
    trade_screening_record.country_code
  end

  sig { returns(T.nilable(String)) }
  def region
    trade_screening_record.region
  end

  sig { returns(T.nilable(String)) }
  def postal_code
    trade_screening_record.postal_code
  end

  sig { returns(T.nilable(String)) }
  def entity_name
    trade_screening_record.entity_name
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_trade_screen_date
    trade_screening_record.last_trade_screen_date
  end

  sig { returns(T::Boolean) }
  def user_owned?
    trade_screening_record.user_owned?
  end

  sig { returns(T.nilable(String)) }
  def linked_admin_path
    return nil unless organization_with_a_linked_record?
    stafftools_user_trade_compliance_path(T.cast(target, ::Organization).linked_trade_screening_record.user)
  end

  private

  sig { returns(T::Boolean) }
  memoize def allowed_to_view_billing_info?
    return false unless trade_screening_record.persisted?

    trade_screening_record.valid_for_owner_type?
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(T::Boolean) }
  attr_reader :show_billing_info

  sig { returns(AccountScreeningProfile) }
  attr_reader :trade_screening_record
end
