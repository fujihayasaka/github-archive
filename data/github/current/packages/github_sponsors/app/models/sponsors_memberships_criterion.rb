# typed: true
# frozen_string_literal: true

class SponsorsMembershipsCriterion < ApplicationRecord::Domain::Sponsors
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  self.table_name = "sponsors_memberships_criteria"

  belongs_to :sponsors_criterion, required: true
  belongs_to :sponsors_listing, required: true
  belongs_to :reviewer, class_name: "User", required: false

  validate :unique_sponsors_criterion

  scope :manual, -> { joins(:sponsors_criterion).merge(SponsorsCriterion.manual) }
  scope :unmet, -> { where(met: false) }

  after_create_commit :instrument_creation
  after_update_commit :instrument_update

  private

  def unique_sponsors_criterion
    return unless sponsors_listing_id

    others = self.class.where(sponsors_criterion_id: sponsors_criterion_id)
      .where(sponsors_listing_id: sponsors_listing_id)
    others = others.where.not(id: id) if persisted?

    if others.exists?
      errors.add(:sponsors_criterion, "has already been taken for Sponsors listing")
    end
  end

  def event_payload
    payload = {
      sponsors_memberships_criterion: self,
      sponsors_criterion: sponsors_criterion,
      met: met,
      criterion_value: value,
      actor: reviewer,
    }

    changes = previous_changes
    payload[:old_met] = changes[:met].first if changes.key?(:met)
    payload[:old_criterion_value] = changes[:value].first if changes.key?(:value)
    payload.merge!(T.must(sponsors_listing).event_context) if sponsors_listing

    payload
  end

  def instrument_creation
    instrument :create
  end

  def instrument_update
    instrument :update
  end
end
