# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::TradeCompliance::SdnSuspensionController < Stafftools::Businesses::TradeComplianceController
  include Stafftools::TradeCompliance::SdnSuspensionActions

  private

  sig { override.returns(Billing::Types::Account) }
  def sdn_target
    this_business
  end
end
