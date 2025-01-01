# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::BusinessAccountOverviewComponent < ApplicationComponent
  include Stafftools::TradeComplianceHelper
  include Stafftools::AccessControlHelper

  sig { returns(::Business) }
  attr_reader :target

  sig { returns(T::Boolean) }
  attr_reader :with_heading

  sig { params(target: ::Business, with_heading: T::Boolean).void }
  def initialize(target:, with_heading: false)
    @target = target
    @with_heading = with_heading
  end

  sig { returns(T::Boolean) }
  def render?
    GitHub.billing_enabled?
  end

  sig { returns(AccountScreeningProfile) }
  memoize def trade_screening_record
    target.trade_screening_record
  end

  sig { returns(String) }
  memoize def humanize_trade_screening_status
    authorized_staffer = stafftools_action_authorized?(controller: Stafftools::TradeCompliance::TradeScreeningRecordsController, action: :index)
    target.humanize_trade_screening_status(authorized_staffer: authorized_staffer)
  end

  sig { returns(String) }
  def trade_audit_log_path
    stafftools_audit_log_events_query(target: target)
  end
end
