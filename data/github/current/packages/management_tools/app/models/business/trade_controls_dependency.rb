# typed: true
# frozen_string_literal: true

module Business::TradeControlsDependency
  extend ActiveSupport::Concern

  included do
  end

  # Public: Check if a business has any trade restrictions that would prevent it from paying for
  # GitHub services. Returns false for now until trade compliance checks are functional for
  # enterprises.
  #
  # Returns a Boolean.
  def has_any_trade_restrictions?
    false
  end

  # Public: Check if a business has full trade restrictions that would prevent it from paying for
  # GitHub services. Returns false for now until trade compliance checks are functional for
  # enterprises.
  #
  # Returns a Boolean.
  def has_full_trade_restrictions?
    false
  end
end
