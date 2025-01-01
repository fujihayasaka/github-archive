# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ReactionOrder < Platform::Inputs::Base
      description "Ways in which lists of reactions can be ordered upon return."

      argument :field, Enums::ReactionOrderField, "The field in which to order reactions by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order reactions by the specified field.", required: true
    end
  end
end
