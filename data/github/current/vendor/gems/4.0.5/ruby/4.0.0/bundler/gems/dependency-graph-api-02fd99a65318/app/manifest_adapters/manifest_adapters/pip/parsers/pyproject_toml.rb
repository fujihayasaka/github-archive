require "semantic"

module ManifestAdapters
  module Pip
    module Parsers
      class PyprojectToml < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
        end

        def name
          name = parsed.dig("project", "name")
          name = parsed.dig("tool", "poetry", "name") unless name.present?
          name || ""
        end

        def version; end

        def dependencies
          @dependencies ||= runtime_dependencies + development_dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "pip",
              "gh.dependency_graph.manifest.type" => "pyproject.toml",
            },
            e
          )
          Failbot.report(e)
          @dependencies = []
        end

        def malformed?
          dependencies
          !!@malformed
        end

        private

        attr_reader :content

        def runtime_dependencies
          dependencies_from_section("dependencies", scope: Types::Scope[:runtime])
        end

        def development_dependencies
          dependencies_from_section("dev-dependencies", scope: Types::Scope[:development])
        end

        # With pyproject.toml files, dependencies might be nested depending on the package manager
        # Because of this, we might have to dig deeper and can't just look at the top level keys
        #  Currently known managers:
        #    PEP621 syntax:                 [project.dependencies] See https://peps.python.org/pep-0621/
        #    default pyproject.toml syntax: [dependencies] https://www.python.org/dev/peps/pep-0508/#grammar
        #    Poetry syntax:                 [tools.poetry.dependencies] https://python-poetry.org/docs/dependency-specification/
        def dependencies_from_section(section, scope:)
          pep621_dependencies = parsed.dig("project", section)
          pyproject_native_dependencies = parsed.dig(section)
          poetry_dependencies = parsed.dig("tool", "poetry", section)

          if pep621_dependencies.present?
            normalized_dependencies = parse_pep621_dependencies(pep621_dependencies, scope)
          elsif pyproject_native_dependencies.present?
            normalized_dependencies = parse_dependencies(pyproject_native_dependencies, PEP508VersionParser.new, scope)
          elsif poetry_dependencies.present?
            normalized_dependencies = parse_dependencies(poetry_dependencies, PoetryVersionParser.new, scope)
            # poetry dependencies sometimes include a "python" key, which we don't care about
            normalized_dependencies.reject! { |dep| dep.package_name == "python" }
          end

          normalized_dependencies || []
        end

        def parse_pep621_dependencies(dependencies, scope)
          pep621_dependencies = dependencies.inject({}) do |res, dependency_string|
            # The version provided by DependencyString won't be parsable by our PEP508
            # parser below, so we'll extract the package name and use the raw requirements
            # string.
            parsed = ManifestAdapters::Pip::DependencyString.parse(dependency_string)
            package_name = parsed[:package_name]
            # Remove the package name so we're only left with the requirements string
            version = dependency_string.sub(package_name, "")
            # TODO: Move this to the PEP508 parser.
            # DependencyString does not support discard trailing requirements like
            # "django>=3.0.0; python_version > 3.1". We'll get rid of everything after
            # ';'.
            res[package_name] = version.split(";")[0]
            res
          end.to_h

          parse_dependencies(pep621_dependencies, PEP508VersionParser.new, scope)
        end

        def parse_dependencies(dependencies, parser, scope)
          # If dependencies is a Hash { package_name => version } then this map works as expected
          # But if dependencies is an Array of string, like "records>0.5.0", then package_name in `map`
          # is the string (e.g. "records>0.5.0") and version is nil
          return dependencies.map do |package_name, version|
            # Make sure we understand the version node
            if version.is_a?(Hash)
              if !version["file"] && !version["path"]
                raw_requirements = version["version"]
              else
                # skip only cases where file and path are used (local dev? )
                next
              end
            else
              raw_requirements = version
            end

            if !raw_requirements.is_a?(String) && raw_requirements.present?
              # We check for .present? above because any absent requirements values are treated as wildcards in pip.
              # Not a string or hash? We don't understand the data but it is likely malformed. The toml parser understands it, but we do not.
              track_dependency_parse_failure("pre-parse", version.to_s)
              next
            end

            begin
              if raw_requirements.present?
                requirements_string = parser.parse_terms_to_requirements(raw_requirements).join(",")
              else
                requirements_string = ""
              end
            rescue Parslet::ParseFailed
              track_dependency_parse_failure(parser.class, raw_requirements)
            end
            create_dependency(package_name, raw_requirements, requirements_string || "", scope)
          end.compact
        end

        def track_dependency_parse_failure(parser, raw_requirements)
          payload = { adapter: :pip,
                      parser: parser.class.name,
                      invalid_range: raw_requirements }
          Instrument.increment("manifest_adapter.invalid_requirements", **payload)
          DependencyGraph.logger.debug(
            "gh.dependency_graph.package_manager" => "pip",
            "gh.dependency_graph.manifest.type" => "pyproject.toml",
            "exception.message" => "invalid requirements",
            "gh.dependency_graph.manifest.is_malformed" => true,
            "gh.dependency_graph.dependency.invalid_requirements" => raw_requirements,
          )
        end

        def create_dependency(package_name, raw_requirements_string, normalized_version_string, scope)
          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            raw_requirements: raw_requirements_string,
            requirements: normalized_version_string,
            scope: scope
          )
        end

        def parsed
          @parsed ||= Tomlrb.parse(content)
        rescue Tomlrb::ParseError, IndexError => e
          DependencyGraph.logger.info("error parsing manifest",
            "gh.dependency_graph.package_manager" => "pip",
            "gh.dependency_graph.manifest.type" => "pyproject.toml",
            "exception.type" => e.class.name,
            "exception.message" => e.message,
          )
          @malformed = true
          @parsed = {}
        end
      end

      class PoetryVersionParser < Parslet::Parser
        # homegrown following: https://python-poetry.org/docs/dependency-specification/
        # only supporting things that are actual version numbers (e.g. not expecting to support file / path)
        SUPPORTED_COMPARATORS = ["~", "^", ">=", ">", "<=", "<"]

        # There isn't an established parsley grammar for this parser (unlike PEP508), but contrasting both is easier
        #  if they both are in the same style.
        # wsp             = ' ' | '\t'
        # version_cmp     = wsp* '~' | '^' | '>=' | '>' | '<=' | '<'
        # version_segment = ( letterOrDigit | '-' | '_' | '*' | '+' | '!' )+
        # version         = wsp* version_segment (. version_segment){0, 2}
        # version_one     = wsp* version_cmp{0,1} version wsp*
        # version_many    = version_one (',' version_one)*
        # versionspec     = ( '(' version_many ')' ) | version_many

        # tabs or spaces
        rule(:wsp)                { str(" ") | str('\t') }
        # " ~", "   >=", "^" -- Note: Ordering of <= and < (same for >= and >) matters for parslet
        rule(:version_cmp)        { wsp.repeat >> (str("~") | str("^") | str(">=") | str(">") | str("<=") | str("<")).as(:one_version_comparator) }
        # "12345", "abc123-_+!foo"
        rule(:version_segment)    { (match("[[:alnum:]]")  | str("-") | str("_") | str("*") | str("+") | str("!")).repeat(1).as(:version_segment) }
        # "123.456.789", "1.2.*", "foo.bar.baz"
        rule(:version)            { wsp.repeat >> (version_segment >> (str(".") >> version_segment).repeat(0, 2)).as(:one_version_bag) }
        # "> 1.2.3", "  === 4.5.6", "< 1.bar"
        rule(:version_one)        { wsp.repeat >> (version_cmp.maybe >> version.repeat(1)).as(:version_one) >> wsp.repeat }
        # "< 1.2.3, > 1.1.0", ">4.foo, <=5.bar"
        rule(:version_many)       { (version_one >> (str(",") >> version_one).repeat).as(:version_many) }
        # "(==1.2.3)", "(<1.2.3, >1.0.0)", "1.2.3"
        rule(:version_spec)       { wsp.repeat >> ((str("(") >> version_many >> str(")")) | version_many).as(:version_spec) >> wsp.repeat }

        root(:version_spec)

        def parse_terms_to_requirements(input)
          result = self.parse(input)
          Array.wrap(self.parse(input).dig(:version_spec, :version_many))
            .flat_map { |x| map_one_term_to_requirements_string(x[:version_one]) }
        end

        def map_one_term_to_requirements_string(input_term)
          # We don't care so much about comparators with this parser -- they generally line up as expected with our own.
          #  What we DO care about are wildcard asterisks, since these aren't just default NPM behavior.
          comparator = (input_term.find { |x| x.dig(:one_version_comparator).present? } || {}).dig(:one_version_comparator)
          version = Array.wrap(input_term
            .find { |x| x.dig(:one_version_bag).present? }
            .dig(:one_version_bag))
            .map { |x| x[:version_segment] }
            .freeze
          return "#{comparator || '='} #{flatten_version(version)}" unless has_wildcard(version)
          return "" if version[0] == "*"

          lower_bound, upper_bound = get_lower_upper_from_wildcard_version(version)
          return [">= #{lower_bound}", "< #{upper_bound}"]
        end

        def flatten_version(version)
          version.join(".")
        end

        def has_wildcard(version)
          version.any? { |segment| segment == "*" }
        end

        # version should be an array of string segments ending in wildcard (e.g. ["1", "2", "*"])
        # return is [lower_bound, upper_bound] where lower_ and upper_bound are requirement strings.
        # Ex: input is ["1", "2", "*"], output is ["1.2.0", "1.3.0"].
        # Upper_bound is exclusive, lower_bound is inclusive per domain rules.
        def get_lower_upper_from_wildcard_version(version)
          version_to_mutate = version.dup
          last_term = version_to_mutate.pop
          if last_term != "*" || version_to_mutate.length < 1
            raise ArgumentError.new("Expected to be called with a wildcard terminated version of at least 2 segment length, got #{version}")
          end

          lower_bound = "#{flatten_version(version_to_mutate)}.0"
          version_to_mutate << (version_to_mutate.pop.to_i + 1).to_s
          upper_bound = "#{flatten_version(version_to_mutate)}.0"

          [lower_bound, upper_bound]
        end
      end

      class PEP508VersionParser < Parslet::Parser
        SUPPORTED_COMPARATORS = ["<", "<=", ">", ">=", "==", "==="]
        # source material, from: https://www.python.org/dev/peps/pep-0508/#grammar
        # wsp           = ' ' | '\t'
        # version_cmp   = wsp* '<' | '<=' | '!=' | '==' | '>=' | '>' | '~=' | '==='
        # version       = wsp* ( letterOrDigit | '-' | '_' | '.' | '*' | '+' | '!' )+
        # version_one   = version_cmp version wsp*
        # version_many  = version_one (wsp* ',' version_one)*
        # versionspec   = ( '(' version_many ')' ) | version_many

        rule(:wsp)                { str(" ") | str('\t') }
        # " ==", "   >=", "===" -- Note: Ordering of <= and < (same for >= and >) matters for parslet
        rule(:version_cmp)        { wsp.repeat >> (str("<=") | str("<") | str("!=") | str("==") | str(">=") | str(">") | str("~=") | str("===")).as(:one_version_comparator) }
        # "1.2.3" also: "   1ab-_.!+*521.bar"
        rule(:version)            { wsp.repeat >> (match("[[:alnum:]]") | str("-") | str("_") | str(".") | str("*") | str("+") | str("!")).repeat(1).as(:one_version_string) }
        # "> 1.2.3"
        rule(:version_one)        { (version_cmp >> version).as(:version_one) >> wsp.repeat }
        # "== 1.2.3 , > 0.1.2, < 2.3.4"
        rule(:version_many)       { (version_one >> (wsp.repeat >> str(",") >> version_one).repeat).as(:version_many) }
        # " ( == 1.2.3 , > 0.1.2 ) " or "< 2.3.4"
        rule(:version_spec)       { wsp.repeat >> ((str("(") >> version_many >> str(")")) | version_many).as(:version_spec) >> wsp.repeat }

        root(:version_spec)

        def parse_terms_to_requirements(input)
          # there is one outlier in input that doesn't line up with the grammar -- the top level asterisk input (*) . We short circuit it.
          return [""] if input.strip == "*"

          Array.wrap(self.parse(input).dig(:version_spec, :version_many))
            .flat_map { |x| map_one_term_to_requirements_string(x[:version_one]) }
        end

        def map_one_term_to_requirements_string(input_term)
          comparator = input_term.dig(:one_version_comparator)
          version = input_term.dig(:one_version_string)

          # What this line does: We will ArgumentError any version strings that don't match our grammar. Why? Because Python has notions we can't accurately
          #  reproduce with asterisk. Example: 1.1a1 is expected to match 1.1.* . This is not something we can easily replicate, and all of our
          #  version expectations have to boil down to semver compliance.
          parsed_version = Versioning::VersionParser.parse(version.to_s, allow_named_versions: false)
          raise ArgumentError.new(
            "Expected a parseable semantic version-like version, got #{version}"
          ) if !parsed_version.parseable?

          if SUPPORTED_COMPARATORS.include? comparator
            # === defined here: https://www.python.org/dev/peps/pep-0440/#arbitrary-equality
            return comparator == "==" || comparator == "===" ?
              "= #{version}" :
              "#{comparator} #{version}"
          elsif "!=" == comparator
            return ["> #{version} || < #{version}"]
          end

          # we're explicitly not supporting ~= , which has really odd behavior around when to consider something the last term ("suffixes" are ignored,
          #  beginning with an alphabet char changes behavior in the last version term.)
        end
      end
    end
  end
end
