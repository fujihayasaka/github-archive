# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityAdvisoryOrder < Platform::Inputs::Base
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      description "Ordering options for security advisory connections"

      argument :field, Enums::SecurityAdvisoryOrderField, "The field to order security advisories by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
