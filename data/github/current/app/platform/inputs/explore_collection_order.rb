# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ExploreCollectionOrder < Platform::Inputs::Base
      description "Ordering options for collection connections."
      visibility :internal

      argument :field, Enums::ExploreCollectionOrderField, "The field to order collections by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
