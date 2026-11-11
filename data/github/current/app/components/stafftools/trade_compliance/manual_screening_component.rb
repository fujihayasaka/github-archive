# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::ManualScreeningComponent < ApplicationComponent
  include StafftoolsHelper
  include Stafftools::TradeComplianceHelper
  include Stafftools::AccessControlHelper

  sig { params(target: T.any(User, Organization, Business)).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def render?
    target.feature_flag_enabled?(:live_sdn_screening, default: true)
  end

  sig { returns(String) }
  def controller_path
    return stafftools_user_trade_compliance_manual_screening_path(target) unless target.is_a?(Business)

    stafftools_enterprise_trade_compliance_manual_screening_path(target)
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = Stafftools::Users::TradeCompliance::ManualScreeningController

    stafftools_action_authorized?(controller: controller, action: :create)
  end

  sig { returns(T::Boolean) }
  memoize def organization_with_a_linked_contact?
    target = self.target
    return false unless target.is_a?(Organization)
    target.has_linked_billing_contact?
  end

  # Trade screening record for displaying trade screening information in stafftools
  sig { returns(AccountScreeningProfile) }
  memoize def trade_screening_record
    target.trade_screening_record
  end

  sig { returns(String) }
  memoize def screening_status
    trade_screening_record.msft_trade_screening_status
  end

  sig { returns(T::Boolean) }
  memoize def manual_screening_allowed?
    trade_screening_record.allowed_to_manually_screen?
  end
end
