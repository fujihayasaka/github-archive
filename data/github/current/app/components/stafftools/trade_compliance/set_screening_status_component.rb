# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::SetScreeningStatusComponent < ApplicationComponent
  include StafftoolsHelper
  include Stafftools::AccessControlHelper
  include Stafftools::TradeComplianceHelper

  sig { params(target: Billing::Types::Account).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def render_button?
    trade_screening_record.persisted?
  end

  sig { returns(String) }
  def actor_type
    return "business" if target.is_a?(Business)
    return "organization" if target.organization?

    "user"
  end

  sig { returns(T::Array[Symbol]) }
  def screening_statuses_list
    if pseudo_record?
      return [:not_screened, :no_hit, :lic_r, :true_match]
    end

    AccountScreeningProfile::VALID_SDN_STATUSES
  end

  sig { returns(String) }
  def screening_profile_status
    return "This account doesn't have a screening record saved and is currently" unless trade_screening_record.persisted?
    return "This account has a pseudo screening record and is currently" if pseudo_record?

    "This account is currently"
  end

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = if target.is_a?(Business)
      Stafftools::Businesses::TradeCompliance::ScreeningStatusController
    else
      Stafftools::Users::TradeCompliance::ScreeningProfileController
    end

    stafftools_action_authorized?(controller: controller, action: :update)
  end

  sig { returns(String) }
  def controller_path
    return stafftools_user_trade_compliance_screening_profile_path(target) unless target.is_a?(Business)

    stafftools_enterprise_trade_compliance_screening_status_path(target)
  end

  private

  # Trade screening record for setting trade screening status in stafftools
  sig { returns(AccountScreeningProfile) }
  memoize def trade_screening_record
    target.trade_screening_record(ignore_linked_record: true)
  end

  sig { returns(T::Boolean) }
  memoize def pseudo_record?
    !target.billing_contact.valid_for_trade_screening?
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :target
end
