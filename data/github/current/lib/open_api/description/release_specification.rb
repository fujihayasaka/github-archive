# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class ReleaseSpecification

      # Public: Parse a release specification.
      #
      # raw_specification - a String or Hash specification (see examples)
      #
      # Examples:
      #
      # A release without any version requirements:
      #
      #     "api.github.com"
      #
      # A release for a specific version requirement:
      #
      #     {"ghe" => "2.19"}
      #
      # A release with multiple version requirements (any is considered a match):
      #
      #     {"ghe" => ["2.19", "2.20"]}
      #
      # Version requirements can use standard Gem::Requirement-style syntax for more complex matches:
      #
      #     {"ghe" => ["2.18", ">= 2.20"]} # For some reason, skip 2.19
      #     {"ghe" => ["~> 2.18"]} # From 2.18 up, but not 3.0
      #
      def self.parse(raw_specification)
        case raw_specification
        when String
          new(raw_specification)
        when Hash
          if raw_specification.size == 1
            release_name = raw_specification.keys.first
            version_requirements = Array(raw_specification.values.last).map do |raw_version_requirement|
              unless raw_version_requirement.is_a?(String)
                raise ArgumentError, "Invalid release version #{raw_version_requirement} - must be a string"
              end

              if raw_version_requirement == "*"
                raw_version_requirement = "> 0"
              end
              Gem::Requirement.create(raw_version_requirement)
            end
            new(release_name, version_requirements)
          else
            raise ArgumentError, "Invalid release specification: #{raw_specification.inspect}"
          end
        end
      end

      attr_reader :release_name, :version_requirements

      def initialize(release_name, version_requirements = [])
        @release_name = release_name
        @version_requirements = version_requirements
      end

      def match?(release)
        return false unless @release_name == release.name
        return true if @version_requirements.empty?
        @version_requirements.any? do |version_requirement|
          version_requirement.satisfied_by?(release.version)
        end
      end
    end
  end
end
