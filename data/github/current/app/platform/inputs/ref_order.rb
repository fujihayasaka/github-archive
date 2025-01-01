# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class RefOrder < Platform::Inputs::Base
      description "Ways in which lists of git refs can be ordered upon return."

      argument :field, Enums::RefOrderField, "The field in which to order refs by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order refs by the specified field.", required: true
    end
  end
end
