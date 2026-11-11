# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SavedCollectionOrder < Platform::Inputs::Base
      description "Ordering options for saved collection connections."
      visibility :internal

      argument :field, Enums::SavedCollectionOrderField, "The field to order saved collections by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
