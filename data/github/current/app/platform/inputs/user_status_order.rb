# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class UserStatusOrder < Platform::Inputs::Base
      docs_category :users
      description "Ordering options for user status connections."

      argument :field, Enums::UserStatusOrderField, "The field to order user statuses by.",
        required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
