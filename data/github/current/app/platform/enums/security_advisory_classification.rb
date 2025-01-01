# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SecurityAdvisoryClassification < Platform::Enums::Base
      description "Classification of the advisory."
      visibility :public

      value "GENERAL", "Classification of general advisories.", value: "general"
      value "MALWARE", "Classification of malware advisories.", value: "malware"
    end
  end
end
