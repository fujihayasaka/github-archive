# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class TeamOrder < Platform::Inputs::Base
      description "Ways in which team connections can be ordered."

      argument :field, Enums::TeamOrderField, "The field in which to order nodes by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
