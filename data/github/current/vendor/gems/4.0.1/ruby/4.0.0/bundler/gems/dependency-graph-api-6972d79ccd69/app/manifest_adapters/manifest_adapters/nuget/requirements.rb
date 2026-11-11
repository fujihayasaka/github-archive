# frozen_string_literal: true
module ManifestAdapters
  module Nuget
    module Requirements
      # Normalize requirements into the dependency graph format
      # https://docs.microsoft.com/en-us/nuget/reference/package-versioning#version-ranges-and-wildcards
      # Lovingly copied from ManifestAdapters::Maven::Requirements <3

      def self.parse(requirements_str)
        return "" if requirements_str.to_s.empty?
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

        payload = { adapter: :nuget,
                    parser: :requirements,
                    invalid_range: requirements_str }
        Instrument.increment("manifest_adapter.invalid_requirements", **payload)
        DependencyGraph.logger.debug("Invalid requirements",
          "gh.dependency_graph.manifest_adapter.requirements" => payload,
          "gh.dependency_graph.manifest.type" => "nuget"
        )

        return ""
      end

      # FIXME: Add support for "6.3-*" - dep graph doesn't support pre-release versions yet
      class Parser < Parslet::Parser
        rule(:space)                      { match('\s').repeat(1) }
        rule(:space?)                     { space.maybe }
        rule(:lparen)                     { str("(") }
        rule(:rparen)                     { str(")") }
        rule(:lbracket)                   { str("[") }
        rule(:rbracket)                   { str("]") }
        rule(:comma)                      { str(",") }
        rule(:comma?)                     { comma.maybe }
        rule(:dot)                        { str(".") }
        rule(:star)                       { str("*") }
        rule(:version_part)               { (match('\w|-')).repeat(1) }


        rule(:version)                    { space? >> ((version_part >> dot).repeat(0) >> version_part).as(:version) >> space? }  # "1.0"

        rule(:wildcard_version)           { ((version_part >> dot).repeat(1)).as(:version) >> star } # "1.*"

        rule(:bare_version)               { version } # "1.0"

        rule(:closed_bare_version)        { lbracket >> version >> rbracket } # "[1.0]"

        rule(:bounded_range)              { lbracket >> version.as(:lower) >> comma >> version.as(:upper) >> rbracket } # "[1.0, 1.2]"
        rule(:bounded_open_range)         { lparen >> version.as(:lower) >> comma >> version.as(:upper) >> rparen } # "(1.0, 1.2)"

        rule(:bounded_left_open_range)    { lparen >> version.as(:lower) >> comma >> version.as(:upper) >> rbracket } # "(1.0, 1.2]"
        rule(:bounded_right_open_range)   { lbracket >> version.as(:lower) >> comma >> version.as(:upper) >> rparen } # "[1.0, 1.2)"

        rule(:left_bounded_range)         { lbracket >> version.as(:lower) >> comma >> rparen } # "[1.1,)"
        rule(:right_bounded_range)        { lparen >> comma >> version.as(:upper)  >> rbracket } # "(,1.1]"

        rule(:left_bounded_open_range)    { lparen >> version.as(:lower) >> comma >> rparen } # "(1.1,)"
        rule(:right_bounded_open_range)   { lparen >> comma >> version.as(:upper) >> rparen } # "(,1.1)"

        rule(:version_specifier)          {
          bare_version.as(:bare_version) |
          wildcard_version.as(:wildcard_version) |
          closed_bare_version.as(:closed_bare_version) |
          bounded_range.as(:bounded_range) |
          bounded_open_range.as(:bounded_open_range) |
          bounded_left_open_range.as(:bounded_left_open_range) |
          bounded_right_open_range.as(:bounded_right_open_range) |
          left_bounded_range.as(:left_bounded_range) |
          right_bounded_range.as(:right_bounded_range) |
          left_bounded_open_range.as(:left_bounded_open_range) |
          right_bounded_open_range.as(:right_bounded_open_range)
        }

        rule(:version_specifier_set)      { version_specifier >> (space? >> comma >> space? >> version_specifier).repeat(0) } # "(,1.0], [1.2,)"

        root(:version_specifier_set)
      end

      class Transformer < Parslet::Transform
        rule(version: simple(:v)) { String(v) }
        # x >= 1.0 * The default Nuget meaning for 1.0 is [1.0,) but with 1.0 recommended.
        # We're going with the = 1.0 here in order to make alerting work as expected but it is subtly different!

        # 1.* - a wildcard version range. Equivalent to [1.0,2.0). Pre-release versions are included when using a wildcard (*).
        # Another example would be 1.2.*, which would be equivalent to [1.2.0, 1.3.0).

        rule(bare_version: simple(:v))                                            { "= #{v}" }
        rule(closed_bare_version: simple(:v))                                     { "= #{v}" }
        rule(wildcard_version: simple(:v))                                        { |dictionary| ">= #{wildcard_lower_bound(dictionary[:v])}, < #{wildcard_upper_bound(dictionary[:v])}" } # need to use this style in order to get class methods

        rule(bounded_range: { lower: simple(:l), upper: simple(:u) })             { ">= #{l}, <= #{u}" }
        rule(bounded_open_range: { lower: simple(:l), upper: simple(:u) })        { "> #{l}, < #{u}" }

        rule(bounded_left_open_range: { lower: simple(:l), upper: simple(:u) })   { "> #{l}, <= #{u}" }
        rule(bounded_right_open_range: { lower: simple(:l), upper: simple(:u) })  { ">= #{l}, < #{u}" }

        rule(left_bounded_range: { lower: simple(:l) })                           { ">= #{l}" }
        rule(right_bounded_range: { upper: simple(:u) })                          { "<= #{u}" }

        rule(left_bounded_open_range: { lower: simple(:l) })                      { "> #{l}" }
        rule(right_bounded_open_range: { upper: simple(:u) })                     { "< #{u}" }

        def self.wildcard_upper_bound(v)
          parts = v.split(".")
          parts[-1] = parts[-1].to_i + 1
          parts.join(".")
        end

        def self.wildcard_lower_bound(v)
          v.split(".").join(".")
        end

      end
    end
  end
end
