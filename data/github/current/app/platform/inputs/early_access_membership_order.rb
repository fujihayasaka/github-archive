# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EarlyAccessMembershipOrder < Platform::Inputs::Base
      description "Ordering options for early access membership connections."
      visibility :internal

      argument :field, Enums::EarlyAccessMembershipOrderField, "The field to order memberships by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
