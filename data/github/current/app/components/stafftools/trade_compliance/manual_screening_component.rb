# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::ManualScreeningComponent < ApplicationComponent
  extend T::Sig
  include StafftoolsHelper
  include Stafftools::AccessControlHelper

  sig { params(target: T.any(User, Organization)).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def render?
    target.feature_enabled?(:live_sdn_screening)
  end

  private

  sig { returns(T.any(User, Organization)) }
  attr_reader :target

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = Stafftools::Users::TradeCompliance::ManualScreeningController

    stafftools_action_authorized?(controller: controller, action: :create)
  end

  sig { returns(T::Boolean) }
  memoize def organization_with_a_linked_record?
    target.has_linked_trade_screening_record?
  end

  sig { returns(String) }
  memoize def screening_status
    target.trade_screening_record.msft_trade_screening_status
  end

  sig { returns(T::Boolean) }
  memoize def manual_screening_allowed?
    target.trade_screening_record.allowed_to_manually_screen?
  end
end
