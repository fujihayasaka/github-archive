# frozen_string_literal: true
module ManifestAdapters
  module Maven
    module Requirements
      # Normalize requirements into the dependency graph format
      # https://maven.apache.org/enforcer/enforcer-rules/versionRanges.html

      def self.parse(requirements_str)
        parse_tree = Parser.new.parse(requirements_str)
        version_specifier = Transformer.new.apply(parse_tree)
        if version_specifier.is_a? Array
          version_specifier.join(" || ")
        else
          version_specifier
        end
      rescue Parslet::ParseFailed
        # If the parse fails we return an empty string, which translates to a wildcard in the dependency graph format.
        # Note that we will fail to parse on things that don't make semantic sense like "(1.0)" or "[,1.0]"

        payload = { adapter: :maven,
                    parser: :requirements,
                    invalid_range: requirements_str }
        Instrument.increment("manifest_adapter.invalid_requirements", **payload)
        DependencyGraph.logger.debug(
          "gh.dependency_graph.dependency.invalid_requirements" => payload,
          "gh.dependency_graph.package_manager" => "maven",
        )

        return ""
      end

      class Parser < ManifestAdapters::Nuget::Requirements::Parser
        # The only difference betweeen the maven and the nuget
        # requirements parser is that maven doesn't support
        # wildcards.

        # We inherit from the nuget parser and make the wildcard rule
        # something that will never match.
        rule(:wildcard_version) { str("").absent? }
      end

      class Transformer < ManifestAdapters::Nuget::Requirements::Transformer

        rule(bare_version: simple(:v))          { |dictionary| "= #{trim_trailing_null_qualifiers(dictionary[:v])}" }
        rule(closed_bare_version: simple(:v))   { |dictionary| "= #{trim_trailing_null_qualifiers(dictionary[:v])}" }

        # Some versions have sections at the end that are "null" only, eg. "4.0.0.Final", "1.0.ga"
        # Those are equivalent to the version without the final section, eg. "4.0.0"
        # This is an imperfect interpretation of the spec but it's good enough for our purposes.
        # https://maven.apache.org/pom.html#version-order-specification
        TRAILING_NULL_QUALIFIERS = /(\.final|\.ga)+$/i.freeze
        def self.trim_trailing_null_qualifiers(v)
          v.gsub(TRAILING_NULL_QUALIFIERS, "")
        end
      end
    end
  end
end
