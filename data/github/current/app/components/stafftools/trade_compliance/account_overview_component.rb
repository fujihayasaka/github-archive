# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::AccountOverviewComponent < ApplicationComponent
  include Stafftools::TradeComplianceHelper

  sig { returns(T.any(::User, ::Organization)) }
  attr_reader :target

  sig { params(target: T.any(::User, ::Organization)).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(String) }
  def account_type
    return "User" if target.user?
    return "Organization" if target.organization?
    "Unknown"
  end

  sig { returns(String) }
  def trade_controls_restriction_type
    return "Spammy" if trade_controls_restriction.type.titleize == "Unrestricted" && target.spammy?

    trade_controls_restriction.type.titleize
  end

  sig { returns(TradeControls::Restriction) }
  memoize def trade_controls_restriction
    target.trade_controls_restriction
  end

  # Trade screening record for displaying trade screening information in stafftools
  sig { returns(AccountScreeningProfile) }
  memoize def trade_screening_record
    target.trade_screening_record
  end

  sig { returns(String) }
  def trade_audit_log_path
    stafftools_audit_log_events_query(target: target)
  end
end
