# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SubIssueOrder < Platform::Inputs::Base
      visibility :under_development
      description "Ordering options for sub-issue issue connections"

      argument :field, Enums::SubIssueOrderField, "The field to order issue types by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
