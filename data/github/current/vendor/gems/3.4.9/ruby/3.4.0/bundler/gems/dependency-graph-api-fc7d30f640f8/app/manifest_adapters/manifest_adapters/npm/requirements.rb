module ManifestAdapters
  module Npm
    # Internal: Normalizes requirements to the dependency graph standard
    # serialization format.
    #
    #  - Replaces '*' with ''
    #  - Replaces space-separated compound requirements with comma-separated
    #    compound requirements
    #  - Prefixes '=' when an operator is omitted
    #  - Prefixes '~>' when the patch is an 'x' e.g. '1.2.x'
    class Requirements
      # Multiple requirements are separated by '||'
      OR_BOUNDARY = /\s+\|\|\s+/

      # Compound requirements are separated by whitespace
      REQUIREMENT_BOUNDARY = /\s+(?=[><~^=])/

      # e.g. "2.3.0 - 2.4.0"
      RANGE = /^[\d.]+\s+-/

      # Matches anything
      WILDCARD = "*"

      # e.g. "2.1.x"
      EMBEDDED_WILDCARD = /^[\d.]+\.x/

      # e.g. "2.1.0"
      NO_OPERATOR = /\A\d/

      # Shorthand for latest version
      LATEST = /\Alatest|beta|[x.]+$/

      def initialize(requirements)
        @requirements = requirements.to_s
      end

      def normalize
        @normalized ||= requirements
          .split(OR_BOUNDARY)
          .map(&method(:normalize_range))
          .join(" || ")
      end

      private

      attr_reader :requirements

      def normalize_range(range)
        range
          .split(REQUIREMENT_BOUNDARY)
          .map(&method(:normalize_requirement))
          .join(",")
      end

      def normalize_requirement(requirement)
        requirement = requirement.sub(/v(?=\d)/, "")

        case requirement
        when RANGE
          lower, upper = requirement.split(/\s+-\s+/)
          ">= #{lower},<= #{upper}"
        when EMBEDDED_WILDCARD
          "~> #{requirement.gsub('x', '0')}"
        when NO_OPERATOR
          "= #{requirement}"
        when WILDCARD, LATEST
          ""
        else requirement
        end
      end
    end
  end
end
