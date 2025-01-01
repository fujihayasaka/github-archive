# typed: true
# frozen_string_literal: true

class Stafftools::TradeCompliance::SetScreeningStatusComponent < ApplicationComponent
  include StafftoolsHelper
  include Stafftools::AccessControlHelper

  def initialize(target:)
    @target = target
  end

  def render_button?
    target.trade_screening_record(ignore_linked_record: true).persisted?
  end

  def actor_type
    return "business" if target.is_a?(Business)
    return "organization" if target.organization?

    "user"
  end

  def screening_statuses_list
    if pseudo_record?
      return [:no_hit, :lic_r, :true_match]
    end

    AccountScreeningProfile::VALID_SDN_STATUSES
  end

  def screening_profile_status
    return "This account doesn't have a screening record saved and is currently" unless trade_screening_record.persisted?
    return "This account has a pseudo screening record and is currently" if pseudo_record?

    "This account is currently"
  end

  def authorized_staffer?
    controller = if target.is_a?(Business)
      Stafftools::Businesses::TradeCompliance::ScreeningStatusController
    else
      Stafftools::Users::TradeCompliance::ScreeningProfileController
    end

    stafftools_action_authorized?(controller: controller, action: :update)
  end

  def controller_path
    return stafftools_user_trade_compliance_screening_profile_path(target) unless target.is_a?(Business)

    stafftools_enterprise_trade_compliance_screening_status_path(target)
  end

  private

  memoize def trade_screening_record
    target.trade_screening_record(ignore_linked_record: true)
  end

  memoize def pseudo_record?
    trade_screening_record.pseudo?
  end

  attr_reader :target
end
