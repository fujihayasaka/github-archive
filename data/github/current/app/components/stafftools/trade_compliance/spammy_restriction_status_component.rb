# typed: true
# frozen_string_literal: true

class Stafftools::TradeCompliance::SpammyRestrictionStatusComponent < ApplicationComponent
  extend T::Sig

  sig { params(billable_entity: ::Billing::Interfaces::BillableEntity, tag: Symbol).void }
  def initialize(billable_entity:, tag: :li)
    @billable_entity = billable_entity
    @tag = tag
  end

  def call
    render Stafftools::StatusListItemComponent.new(status: :error, message: message,
      test_selector: "spammy-restriction-status", tag: tag)
  end

  def render?
    return false unless billable_entity.user?

    billable_entity.spammy? && !billable_entity.has_any_trade_restrictions?
  end

  private

  attr_reader :billable_entity, :tag

  # Private: Returns the current spammy restriction status on the billable_entity
  #
  # Returns a String.
  def message
    if billable_entity.scheduled_ofac_downgrade
      "Spammy restriction scheduled for #{billable_entity.scheduled_ofac_downgrade.downgrade_on}"
    elsif billable_entity.spammy_downgrade_finalized?
      "Spammy restriction finalized on #{billable_entity.trade_restriction_finalized_date}"
    else
      "Spammy restricted"
    end
  end
end
