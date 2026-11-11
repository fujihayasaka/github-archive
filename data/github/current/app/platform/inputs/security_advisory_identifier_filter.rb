# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SecurityAdvisoryIdentifierFilter < Platform::Inputs::Base
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]


      description "An advisory identifier to filter results on."

      argument :type, Enums::SecurityAdvisoryIdentifierType, "The identifier type.", required: true
      argument :value, String, "The identifier string. Supports exact or partial matching.", required: true
    end
  end
end
