# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryRuleOrder < Platform::Inputs::Base
      description "Ordering options for repository rules."

      argument :field, Enums::RepositoryRuleOrderField,
        "The field to order repository rules by.",
        required: true

      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
