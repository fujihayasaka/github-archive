# DependencyString normalizes PyPI requirements to the dependency graph format.
# Some key differences:
# - The dependency graph uses '=' rather than '=='
# - The dependency graph uses '~>' rather than '~='
# - The dependency graph doesn't support version exclusions
module ManifestAdapters
  module Pip
    class DependencyString
      OPERATORS = %w{ ^=<>~! }

      PACKAGE_NAME = /([A-Za-z0-9._-]+)(\[\w+(?:,\s*\w+\s*)*\])?\s*([^;]*)?/
      VALID_REQUIREMENTS = /\A[#{OPERATORS}]+\s*\d/
      REQUIREMENTS = /([#{OPERATORS}]+)\s*(\d[^\s]*)/
      URLSPEC_REQUIREMENTS = /@\s*(#{URI::DEFAULT_PARSER.make_regexp})\z/
      NORMALIZATION_PACKAGE_NAME = /[-_.]+/

      ParseError = Class.new(ArgumentError)

      def self.parse(dependency)
        _, package_name, _, requirement_set = dependency.match(PACKAGE_NAME).to_a
        raise ParseError.new(package_name) if package_name.blank?

        {
          package_name: package_name.strip,
          requirements: parse_requirement_set(requirement_set.strip)
        }
      end

      # normalize the package name per rule
      # https://www.python.org/dev/peps/pep-0503/
      def self.normalize_package_name(package)
        package.gsub(NORMALIZATION_PACKAGE_NAME, "-").downcase
      end

      def self.parse_requirement_set(requirement_set)
        requirement_set.to_s.
          gsub(/#.*/, ""). # remove comments like this very same one
          gsub(/\(|\)/, ""). # remove extra parens
          split(","). # sometimes req strings look like "foo > 1.0, < 2.0"
          map { |requirements| parse_requirements(requirements.strip) }.
          join(",")
      end

      def self.parse_requirements(requirements)
        return "" if requirements == "*"

        if requirements.present? && requirements !~ VALID_REQUIREMENTS && requirements !~ URLSPEC_REQUIREMENTS
          raise ParseError.new("Error parsing requirements: #{requirements.inspect}")
        end

        _, operator, version = requirements.match(REQUIREMENTS).to_a

        return "" unless operator && version

        operator.gsub!(/=+/, "=")
        operator.gsub!("~=", "~>")

        if operator == "!="
          return "< #{version} || > #{version}"
        end

        "#{operator} #{version}"
      end
    end
  end
end
