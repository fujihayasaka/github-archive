# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseMemberOrder < Platform::Inputs::Base
      description "Ordering options for enterprise member connections."

      argument :field, Enums::EnterpriseMemberOrderField, "The field to order enterprise members by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
