# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SavedViewOrder < Platform::Inputs::Base
      description "Ordering options for saved view connections."
      visibility :internal

      argument :field, Enums::SavedViewOrderField, "The field to order saved views by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
