# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class LanguageOrder < Platform::Inputs::Base
      description "Ordering options for language connections."

      argument :field, Enums::LanguageOrderField, "The field to order languages by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
