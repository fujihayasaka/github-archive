# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SecurityAdvisoryIdentifierType < Platform::Enums::Base
      docs_category :security_advisories
      visibility :public

      description "Identifier formats available for advisories."

      value "CVE", "Common Vulnerabilities and Exposures Identifier."
      value "GHSA", "GitHub Security Advisory ID."
    end
  end
end
