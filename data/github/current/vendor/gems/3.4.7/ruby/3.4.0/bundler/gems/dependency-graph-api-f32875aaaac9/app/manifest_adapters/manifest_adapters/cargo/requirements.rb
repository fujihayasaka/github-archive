# frozen_string_literal: true

module ManifestAdapters
  module Cargo
    module Requirements
      # Normalize Cargo.toml requirements string into the dependency graph format
      def self.parse(requirements_str)
        return "" if requirements_str.to_s.empty?

        parse_tree = Parser.new.parse(requirements_str)

        requirements = []
        Transformer.new.apply(parse_tree, out: requirements)

        raise ::Parslet::ParseFailed.new("no matches", "for parse tree: #{parse_tree}") if requirements.empty?
        return requirements.join(", "), false
      rescue ::Parslet::ParseFailed => e
        # If the parse fails we return an empty string, which translates to a wildcard in the dependency graph format.
        # Note that we will fail to parse on things that don't make semantic sense
        payload = { adapter: :cargo_toml,
                    parser: :requirements,
                    invalid_range: requirements_str }
        Instrument.increment("manifest_adapter.invalid_requirements", **payload)
        DependencyGraph.logger.debug("Invalid payload with error",
          "gh.dependency_graph.package_manager" => "cargo",
          "gh.dependency_graph.manifest.is_malformed" => true,
          "gh.dependency_graph.manifest_adapter.invalid_payload" => payload,
          "exception.message" => e.message,
          "gh.dependency_graph.manifest_adapter.parse_failure_cause" => e.parse_failure_cause,
        )

        return "", true
      end

      class Parser < ::Parslet::Parser
        rule(:space)                      { match('\s').repeat }
        rule(:space?)                     { space.maybe }
        rule(:comma)                      { str(",") }
        rule(:comma?)                     { comma.maybe }
        rule(:caret)                      { str("^") }
        rule(:tilde)                      { str("~") }
        rule(:dot)                        { str(".") }
        rule(:wildcard)                   { str("*") }
        rule(:zero)                       { str("0") }
        rule(:digits)                     { match("[0-9]").repeat }
        rule(:number)                     { zero | (match("[1-9]") >> digits) }
        rule(:lte)                        { str("<=") }
        rule(:gte)                        { str(">=") }
        rule(:lt)                         { str("<") }
        rule(:gt)                         { str(">") }
        rule(:eq)                         { str("=")  }
        rule(:suffix)                     { str("-") >> match('[^, \n\r\t]').repeat(1, nil) }

        # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#specifying-dependencies-from-cratesio
        rule(:prefix?)                    { (caret | tilde).maybe.as(:prefix) }
        rule(:num_or_wild)                { number.as(:number) | wildcard.as(:wildcard) }
        rule(:major_minor_patch)          { number.as(:major) >> dot >> number.as(:minor) >> dot >> num_or_wild.as(:patch) }
        rule(:major_minor)                { number.as(:major) >> dot >> num_or_wild.as(:minor) }
        rule(:major_only)                 { num_or_wild.as(:major) }
        rule(:semver)                     { ((major_minor_patch | major_minor | major_only) >> suffix.maybe.as(:suffix)).as(:semver) }
        rule(:version_spec)               { space? >> prefix? >> space? >> semver >> space? }

        # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#comparison-requirements
        rule(:bound_op)                   { gte | lte | gt | lt | eq }
        rule(:single_bound)               { space? >> bound_op.as(:operator) >> space? >> semver >> space? }

        # ordered, comma-separated version range
        rule(:lower_bound_op)             { gte | gt }
        rule(:lower_bound)                { space? >> lower_bound_op.as(:lower_op) >> space? >> semver >> space? }
        rule(:upper_bound_op)             { lte | lt }
        rule(:upper_bound)                { space? >> upper_bound_op.as(:upper_op) >> space? >> semver >> space? }
        rule(:version_range)              { lower_bound.as(:lower_left) >> comma >> upper_bound.as(:upper_right) }
        rule(:reversed_range)             { upper_bound.as(:upper_left) >> comma >> lower_bound.as(:lower_right) }

        # a well-formed Cargo.toml version string resolves to exactly one of these
        rule(:requirements)               { version_range | reversed_range | single_bound | version_spec }
        root(:requirements)
      end

      # transforms Parslet ASTs into well-formed Dependency Graph version requriement strings
      class Transformer < ::Parslet::Transform
        rule(semver: subtree(:v))                                 { out << ExpandBound.new(p, v).eval }     # "1", "1.2", "1.2.3","*", "2.*"
        rule(prefix: simple(:p), semver: subtree(:v))             { out << ExpandBound.new(p, v).eval }     # "~1", "~2.0", "~1.2.*", "~4.5.6"
        rule(operator: simple(:op), semver: subtree(:v))          { out << ResolveBound.new(op, v).eval }   # "= 1.2", ">=1.2.3", "< 1.*"
        rule(lower_op: simple(:op), semver: subtree(:v))          { out <<  ResolveBound.new(op, v).eval }  # ">1.2", ">= 1.2.3", "> 3"
        rule(upper_op: simple(:op), semver: subtree(:v))          { out <<  ResolveBound.new(op, v).eval }  # "<1.2", "<= 1.2.3", "< 3"
        rule(upper_left: subtree(:ul), lower_right: subtree(:lr)) { out.reverse! }                          # in: "<2.3.4", ">=1.1.0" out: ">= 1.1.0, < 2.3.4"

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

        # wildcards other than major-version are treated
        # identically to missing semver elements
        def self.strip_trailing_wildcards(version)
          out = version.dup
          out[:patch] = nil if dig(out, :patch, :wildcard)
          out[:minor] = nil if dig(out, :minor, :wildcard)

          out
        end

        # does this semver include any wildcard elements?
        def self.is_wildcard_version(version)
          [:patch, :minor, :major].any? do |elem|
            dig(version, elem, :wildcard)
          end
        end

        # is this semver fully specified (x.y.z) or partial?
        def self.is_partial_version(version)
          [:patch, :minor, :major].any? do |elem|
            version[elem].nil?
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
        # Hash with :wildcard key => Integer(0)
        def self.version_to_number(elem)
          case elem
          when ::Parslet::Slice
            return elem.to_i
          when Hash
            return 0 if dig(elem, :wildcard)
            dig(elem, :number).to_i
          when NilClass
            return 0
          else
            raise ::Parslet::ParseFailed.new("transformer", "unexpected version element: #{elem} of type #{elem.class}")
          end
        end
      end

      class ResolveBound
        # resolve a well-formed version bound with comparison operator
        def initialize(operator, version)
          @operator = operator.to_s
          @version = version
        end
        attr_reader :operator, :version

        def eval
          # naively resolve numerical versions we can adjust in special-cases, if needed
          maj, min, patch = Transformer::resolve_version(version)
          # make a temp copy in case non-equality comparison ops must be updated for output
          op = operator
          # suffix is optional but we capture it if one is present.
          # there's more to version range expansion once we support suffix!
          # https://doc.rust-lang.org/cargo/reference/resolver.html#pre-releases
          suffix = version[:suffix] ? version[:suffix].to_s : ""

          # handle special cases
          if Transformer::dig(version, :major, :wildcard)
            raise ::Parslet::ParseFailed.new("transformer", "invalid wildcard on major version in explicit bound: #{version}")
          end

          if Transformer::is_wildcard_version(version) || Transformer::is_partial_version(version)
            raise ::Parslet::ParseFailed.new("transformer", "wildcard or partially-specified bounds cannot include a suffix") if !suffix.empty?

            case operator
            when "="
              # partially specified or wildcard-suffixed semvers using "=" operator
              # are equivalent to expanded single bounds using tilde mode. note: the
              # parser ensures versions that can reach this clause are always a single-bound.
              return ExpandBound.new("~", version).eval
             when ">="
               # GTE bounds are easily resolved! use vanilla resolve_version and treat
               # missing or wildcarded entries as 0s like that method does anyway
             when ">"
               op = ">="
               if version[:minor].nil? || Transformer::dig(version, :minor, :wildcard)
                 # special case: "> x", "> x.*"
                 maj += 1
               else
                 # special case: "> x.y", "> x.y.*"
                 min += 1
               end
             when "<"
               # LT bounds are easily resolved! use vanilla resolve_version and treat
               # missing or wildcarded entries as 0s like that method does anyway!
             when "<="
               op = "<"
               if version[:minor].nil? || Transformer::dig(version, :minor, :wildcard)
                 # special case: "<= x", "<= x.*"
                 maj += 1
               else
                 # special case: "<= x.y", "<= x.y.*"
                 min += 1
               end
             end
           end

           # fully specified bound w/comparison operator only requires formatting
          "#{op} #{maj}.#{min}.#{patch}#{suffix}"
        end
      end

      # expand a single bound declaration (default, caret, or tilde mode) into a range.
      # strangely, this is the default behavior and pinning requires an operator "= 1.2.3"
      # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#specifying-dependencies-from-cratesio
      class ExpandBound
        def initialize(prefix, version)
          @prefix = prefix.to_s
          @version = version
        end
        attr_reader :prefix, :version

        def eval
          # handle special case: "*", "~*", "^*"
          if Transformer::dig(version, :major, :wildcard)
            if !prefix.blank? || !version[:suffix].nil?
              raise ::Parslet::ParseFailed.new("transformer", "single wildcard cannot be prefixed or suffixed")
            else
              return ">= 0.0.0"
            end
          end

          # flags used in special-case checks
          is_tilde_mode = prefix == "~"
          patch_is_wildcard = Transformer::dig(version, :patch, :wildcard)

          # suffix is optional but we capture it if one is present.
          # there's more to version range expansion once we support suffix!
          # https://doc.rust-lang.org/cargo/reference/resolver.html#pre-releases
          suffix = version[:suffix] ? version[:suffix].to_s : ""
          if Transformer::is_wildcard_version(version) || Transformer::is_partial_version(version)
            raise ::Parslet::ParseFailed.new("transformer", "wildcard or partially-specified bounds cannot include a suffix") if !suffix.empty?
          end

          # trailing wildcards are the same as missing semver elements
          semver = Transformer::strip_trailing_wildcards(version)

          # convert version to integers; init upper bound as same
          l_maj, l_min, l_patch = Transformer::resolve_version(semver)
          u_maj, u_min, u_patch = l_maj, l_min, l_patch

          # special cases: range expansions are more strict on major version 0
          if l_maj == 0 && semver[:minor].nil?
            # special case "0": 0 := >=0.0.0, <1.0.0
            u_maj, u_min, u_patch = 1, 0, 0
          elsif l_maj == 0 && l_min == 0 && !semver[:patch].nil?
            # special case "0.0.n": 0.0.0 := >=0.0.0, <0.0.1
            u_patch += 1
          elsif l_maj == 0
            # special cases "0.0", "0.n.m" (n != 0): 0.1.2 := >=0.1.2, <0.2.0
            u_min, u_patch = u_min + 1, 0

          # TILDE MODE: strict upper bounds when major version >0
          # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#tilde-requirements
          elsif is_tilde_mode
            if semver[:minor].nil?
              # special case major-version only: ~1 := >=1.0.0, <2.0.0
              u_maj += 1
            else
              # default tilde-mode: upper bound is minor version successor
              # ~1.2   := >=1.2.0, <1.3.0
              # ~1.2.3 := >=1.2.3, <1.3.0
              u_min += 1
              u_patch = 0
            end

          # DEFAULT MODE: upper bound is always next major version, if major version >0
          # "caret mode" is the default so treat "^1.2" as "1.2" and so on
          # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#caret-requirements
          else
            if patch_is_wildcard
              # special case wildcard in the "patch" element:
              # 1.2.*   :=  >=1.2.0, <1.3.0
              u_min, u_patch = u_min + 1, 0
            else
              # 1      :=  >=1.0.0, <2.0.0
              # 1.2    :=  >=1.2.0, <2.0.0
              # 1.0.0  :=  >=1.0.0, <2.0.0
              # 1.2.0  :=  >=1.2.0, <2.0.0
              # 1.2.3  :=  >=1.2.3, <2.0.0
              u_maj, u_min, u_patch = u_maj + 1, 0, 0
            end
          end

          ">= #{l_maj}.#{l_min}.#{l_patch}#{suffix}, < #{u_maj}.#{u_min}.#{u_patch}"
        end
      end
    end
  end
end
