# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DismissReason < Platform::Enums::Base
      description "The possible reasons that a Dependabot alert was dismissed."

      RepositoryVulnerabilityAlert::DISMISS_REASONS.each do |key, reason|
        value self.convert_string_to_enum_value(key.to_s), reason, value: reason
      end
    end
  end
end
