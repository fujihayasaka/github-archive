# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class UserListOrder < Platform::Inputs::Base
      mobile_only true
      description "Ordering options for user list connections."

      argument :field, Enums::UserListOrderField, "The field to order user lists by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order user lists by the specified field", required: true
    end
  end
end
