# frozen_string_literal: true

require "parslet"
require "failbot"
require_relative "utilities"

module Pub
  module Requirements
    include Logging

    # Normalize Pub requirements string into the dependency graph format
    def self.parse(requirements_str)
      if requirements_str.to_s.empty?
        return "", false
      end

      parse_tree = Parser.new.parse(requirements_str)

      requirements = []
      Transformer.new.apply(parse_tree, out: requirements)

      raise ::Parslet::ParseFailed.new("no matches", "for parse tree: #{parse_tree}") if requirements.empty?
      return requirements.join(", "), false
    rescue ::Parslet::ParseFailed => e
      # If the parse fails we return an empty string, signaling an undetermined
      # version range for this PackageRelease's dependency. Treatment varies
      # across ecosystem PMAs but this is not unusual.
      Failbot.report(e,
        "gh.dependency_graph.package_manager" => :pub,
        "gh.dependency_graph.package_metadata_parser" => :requirements,
        "gh.dependency_graph.parse_failure_cause" => e.parse_failure_cause,
        "gh.dependency_graph.invalid_range_string" => requirements_str
      )

      return "", true
    end

    class Parser < ::Parslet::Parser
      rule(:space)                      { match('\s').repeat }
      rule(:space?)                     { space.maybe }
      rule(:caret)                      { str("^") }
      rule(:dot)                        { str(".") }
      rule(:zero)                       { str("0") }
      rule(:digits)                     { match("[0-9]").repeat }
      rule(:number)                     { zero | (match("[1-9]") >> digits) }
      rule(:lte)                        { str("<=") }
      rule(:gte)                        { str(">=") }
      rule(:lt)                         { str("<") }
      rule(:gt)                         { str(">") }
      rule(:eq)                         { str("=")  }
      rule(:plus)                       { str("+")  }
      rule(:minus)                      { str("-")  }
      rule(:suffix)                     { (plus | minus) >> match('[^ \n\r\t]').repeat(1, nil) }
      rule(:prefix?)                    { caret.maybe.as(:prefix) }
      rule(:any)                        { str("any") }
      rule(:major_minor_patch)          { number.as(:major) >> dot >> number.as(:minor) >> dot >> number.as(:patch) }
      rule(:semver)                     { (major_minor_patch >> suffix.maybe.as(:suffix)).as(:semver) }

      # single clause version spec
      rule(:version_spec)               { space? >> (any.as(:any) | (prefix? >> semver)) >> space? }

      # single range bound
      rule(:bound_op)                   { gte | lte | gt | lt | eq }
      rule(:single_bound)               { space? >> bound_op.as(:operator) >> space? >> semver >> space? }

      # ordered, space-separated version range
      rule(:lower_bound_op)             { gte | gt }
      rule(:lower_bound)                { space? >> lower_bound_op.as(:lower_op) >> space? >> semver >> space? }
      rule(:upper_bound_op)             { lte | lt }
      rule(:upper_bound)                { space? >> upper_bound_op.as(:upper_op) >> space? >> semver >> space? }
      rule(:version_range)              { lower_bound.as(:lower_left) >> space >> upper_bound.as(:upper_right) }
      rule(:reversed_range)             { upper_bound.as(:upper_left) >> space >> lower_bound.as(:lower_right) }

      # a well-formed pubspec version string resolves to exactly one of these
      rule(:requirements)               { version_range | reversed_range | single_bound | version_spec }
      root(:requirements)
    end

    # transforms Parslet ASTs into well-formed Dependency Graph version requriement strings
    class Transformer < ::Parslet::Transform
      rule(any: simple(:any))                                   { out << "*" }                            # "any"
      rule(semver: subtree(:v))                                 { out << ExpandBound.new(p, v).eval }     # "1.2.3", "0.1.2"
      rule(prefix: simple(:p), semver: subtree(:v))             { out << ExpandBound.new(p, v).eval }     # "^0.1.2", "^4.5.6"

      rule(operator: simple(:op), semver: subtree(:v))          { out <<  ResolveBound.new(op, v).eval }  # ">=1.2.3", "<1.2.3"
      rule(lower_op: simple(:op), semver: subtree(:v))          { out <<  ResolveBound.new(op, v).eval }  # ">1.2.3", ">=1.2.3"
      rule(upper_op: simple(:op), semver: subtree(:v))          { out <<  ResolveBound.new(op, v).eval }  # "<1.2.3", "<=1.2.3"

      rule(upper_left: subtree(:ul), lower_right: subtree(:lr)) { out.reverse! } # in: "<2.3.4", ">=1.1.0" out: ">= 1.1.0, < 2.3.4"

      # leaf values in the AST are ::Parslet::Slice and must be unwrapped
      def self.dig(tree, *keys)
        return nil if tree.nil? || keys.empty? || !tree.is_a?(Hash)

        head, *tail = keys
        case tree[head]
        when Hash
          dig(tree[head], *tail)
        when ::Parslet::Slice
          return nil if !tail.empty?
          tree[head].to_s
        when NilClass
          nil
        end
      end

      # resolve elements of semver into numbers
      def self.resolve_version(version)
        maj = version_to_number(version[:major])
        min = version_to_number(version[:minor])
        patch = version_to_number(version[:patch])

        return maj, min, patch
      end

      # each element of the semver can have one of 4 values:
      # nil                     => Integer(0)
      # number as a String      => convert to Integer
      # Hash with :number key   => convert v[:number] to Integer
      def self.version_to_number(elem)
        case elem
        when ::Parslet::Slice
          return elem.to_i
        when Hash
          dig(elem, :number).to_i
        when NilClass
          return 0
        else
          raise ::Parslet::ParseFailed.new("transformer", "unexpected version element: #{elem} of type #{elem.class}")
        end
      end
    end

    # resolve a well-formed version bound with comparison operator
    class ResolveBound
      def initialize(operator, version)
        @operator = operator.to_s
        @version = version
      end
      attr_reader :operator, :version

      def eval
        # naively resolve numerical versions we can adjust in special-cases, if needed
        maj, min, patch = Transformer::resolve_version(version)

        # "<0.0.0" is nonsense, bail
        if operator == "<" && maj == 0 && min == 0 && patch == 0
          raise ::Parslet::ParseFailed.new("transformer", "no valid version exists less than version 0.0.0")
        end

        # suffix is optional but we capture it if one is present.
        # there's more to version range expansion once we support suffix!
        # https://dart.dev/tools/pub/pubspec#version
        suffix = version[:suffix] ? version[:suffix].to_s : ""

         # fully specified bound w/comparison operator only requires formatting
        "#{operator} #{maj}.#{min}.#{patch}#{suffix}"
      end
    end

    # expand a single bound declaration (default or caret-prefixed) into range or pinned semver
    # https://dart.dev/tools/pub/pubspec#version
    class ExpandBound
      def initialize(prefix, version)
        @prefix = prefix.to_s
        @version = version
      end
      attr_reader :prefix, :version

      def eval
        # flags used in special-case checks
        is_caret_mode = prefix == "^"

        # suffix is optional but we capture it if one is present.
        # there's more to version range expansion once we support suffix!
        # https://dart.dev/tools/pub/pubspec#version
        suffix = version[:suffix] ? version[:suffix].to_s : ""

        # convert version to integers; init upper bound as same
        l_maj, l_min, l_patch = Transformer::resolve_version(version)

        # default case: unprefixed, fully-specified semver pins a version
        if !is_caret_mode
          return "= #{l_maj}.#{l_min}.#{l_patch}#{suffix}"
        end

        # caret mode expands to a range, depending on major version
        u_maj, u_min, u_patch = l_maj, l_min, l_patch
        if l_maj == 0
          # ^0.4.5  :=  >=0.4.5, <0.5.0
          u_min, u_patch = u_min + 1, 0
        else
          # ^1.2.3  :=  >=1.2.3, <2.0.0
          u_maj, u_min, u_patch = u_maj + 1, 0, 0
        end

        ">= #{l_maj}.#{l_min}.#{l_patch}#{suffix}, < #{u_maj}.#{u_min}.#{u_patch}"
      end
    end
  end
end
