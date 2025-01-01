# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class FollowOrder < Platform::Inputs::Base
      description "Ordering options for user follow connections."

      visibility :under_development

      argument :field, Enums::FollowOrderField, "The field to order follows by.",
        required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
