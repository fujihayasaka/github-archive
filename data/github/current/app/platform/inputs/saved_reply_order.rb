# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SavedReplyOrder < Platform::Inputs::Base
      description "Ordering options for saved reply connections."

      argument :field, Enums::SavedReplyOrderField, "The field to order saved replies by.",
        required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
