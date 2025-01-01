# typed: strict
# frozen_string_literal: true

module Stafftools::Businesses::TradeCompliance::SharedControllerMethods
  include Stafftools::TradeCompliance::SharedControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Stafftools::Businesses::BusinessBaseController }

  sig { override.returns(Business) }
  def target
    this_business
  end
end
