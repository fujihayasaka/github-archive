# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class ActivityOrder < Platform::Inputs::Base
      description "Ordering options for activity connections"

      argument :field, Enums::ActivityOrderField, "The field to order activity by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
