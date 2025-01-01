# typed: strict
# frozen_string_literal: true

module Business::TradeControlsDependency
  extend ActiveSupport::Concern

  # Public: Check if a business has any trade restrictions that would prevent it from paying for
  # GitHub services. Returns false for now until trade compliance checks are functional for
  # enterprises.
  sig { returns(T::Boolean) }
  def has_any_trade_restrictions?
    false
  end

  # Public: Check if a business has full trade restrictions that would prevent it from paying for
  # GitHub services. Returns false for now until trade compliance checks are functional for
  # enterprises.
  sig { returns(T::Boolean) }
  def has_full_trade_restrictions?
    false
  end

  sig { returns(T.nilable(OFACDowngrade)) }
  def scheduled_ofac_downgrade
    nil
  end

  # Public: Is this user's trade restriction finalized?
  sig { returns(T::Boolean) }
  def trade_restriction_finalized?
    has_any_trade_restrictions? && complete_ofac_downgrade.present?
  end

  # Public: Is this user's spammy downgrade finalized?
  sig { returns(T::Boolean) }
  def spammy_downgrade_finalized?
    false
  end

  # Public: Date when the trade restriction downgrade was completed
  sig { returns(T.nilable(Date)) }
  def trade_restriction_finalized_date
    nil
  end

  # Private: Returns the last completed OFAC downgrade if it exists
  sig { returns(T.nilable(OFACDowngrade)) }
  def complete_ofac_downgrade
    nil
  end

  sig { void }
  def send_trade_controls_allowed_status_email
    T.bind(self, Business)
    TradeScreeningMailer.owner_profile_allowed_status(self).deliver_later
  end

  sig { void }
  def send_trade_controls_not_allowed_status_email
    T.bind(self, Business)
    TradeScreeningMailer.owner_profile_not_allowed_status(self).deliver_later
  end

  sig { void }
  def send_trade_controls_data_needs_fixing_status_email
    T.bind(self, Business)
    TradeScreeningMailer.owner_profile_data_needs_fixing(self).deliver_later
  end
end
