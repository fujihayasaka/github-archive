# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueTypeOrder < Platform::Inputs::Base
      description "Ordering options for issue types connections"

      argument :field, Enums::IssueTypeOrderField, "The field to order issue types by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
