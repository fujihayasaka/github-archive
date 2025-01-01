# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueDependencyOrder < Platform::Inputs::Base
      description "Ordering options issue dependencies"

      argument :field, Enums::IssueDependencyOrderField, "The field to order issue dependencies by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
