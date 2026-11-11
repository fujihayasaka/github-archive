# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class OrganizationOrder < Platform::Inputs::Base
      description "Ordering options for organization connections."

      argument :field, Enums::OrganizationOrderField, "The field to order organizations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
