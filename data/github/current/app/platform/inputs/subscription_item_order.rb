# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SubscriptionItemOrder < Platform::Inputs::Base
      description "Ordering options for subscription item connections."
      visibility :internal

      argument :field, Enums::SubscriptionItemOrderField, "The field to order subscription items by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
