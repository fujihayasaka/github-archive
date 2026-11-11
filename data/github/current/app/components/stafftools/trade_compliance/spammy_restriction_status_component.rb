# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::SpammyRestrictionStatusComponent < ApplicationComponent
  sig { params(billable_entity: Billing::Types::Account, tag: Symbol).void }
  def initialize(billable_entity:, tag: :li)
    @billable_entity = billable_entity
    @tag = tag
  end

  sig { returns String }
  def call
    render Stafftools::StatusListItemComponent.new(status: :error, message: message,
      test_selector: "spammy-restriction-status", tag: tag)
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless billable_entity.user?

    billable_entity.spammy? && !billable_entity.has_any_trade_restrictions?
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :billable_entity
  sig { returns(Symbol) }
  attr_reader :tag

  sig { returns(T.nilable(OFACDowngrade)) }
  memoize def scheduled_ofac_downgrade
    billable_entity.scheduled_ofac_downgrade
  end

  # Private: Returns the current spammy restriction status on the billable_entity
  sig { returns(String) }
  def message
    if scheduled_ofac_downgrade = self.scheduled_ofac_downgrade
      "Spammy restriction scheduled for #{scheduled_ofac_downgrade.downgrade_on}"
    elsif billable_entity.spammy_downgrade_finalized?
      "Spammy restriction finalized on #{billable_entity.trade_restriction_finalized_date}"
    else
      "Spammy restricted"
    end
  end
end
