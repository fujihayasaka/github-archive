# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueFieldOrder < Platform::Inputs::Base
      description "Ordering options for issue field connections"

      argument :field, Enums::IssueFieldOrderField, "The field to order issue fields by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
