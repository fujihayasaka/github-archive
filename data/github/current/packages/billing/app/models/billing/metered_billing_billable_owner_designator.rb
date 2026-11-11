# typed: true
# frozen_string_literal: true

class Billing::MeteredBillingBillableOwnerDesignator
  def self.attributes_for(owner)
    new(owner).to_h
  end

  def initialize(owner)
    @owner = owner
  end

  def billable_owner
    @billable_owner ||= owner.billable_owner
  end

  def to_h
    {
      billable_owner_id: billable_owner.id,
      billable_owner_type: billable_owner.class.polymorphic_name,
    }
  end

  private

  attr_reader :owner
end
