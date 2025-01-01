# typed: true
# frozen_string_literal: true
module Codespaces
  module BillableOwnerEntitySerializer
    # possible user type values from lib/hydro/schemas/github/v1/entities/billing_plan_owner_pb.rb
    USER_TYPES = {
      "User" => :TYPE_USER,
      "Organization" => :TYPE_ORGANIZATION,
      "Business" => :TYPE_BUSINESS,
    }

    def self.serialize(billable_owner)
      {
        global_id: billable_owner.global_relay_id,
        database_id: billable_owner.id,
        type: USER_TYPES.fetch(billable_owner.class.name, :TYPE_UNKNOWN),
        name: billable_owner.login, # rubocop:disable GitHub/DoNotAllowLogin
        tier: Codespaces::Tier.for_billable_owner(billable_owner).tier,
        spammy: billable_owner.spammy?,
        suspended: billable_owner.suspended?,
        spamurai_classification: self.spamurai_classification(billable_owner),
      }
    end

    def self.spamurai_classification(billable_owner)
      if billable_owner.spammy?
        :SPAMMY
      elsif billable_owner.hammy?
        :HAMMY
      else
        :SPAMURAI_CLASSIFICATION_UNKNOWN
      end
    end
    private_class_method :spamurai_classification

  end
end
