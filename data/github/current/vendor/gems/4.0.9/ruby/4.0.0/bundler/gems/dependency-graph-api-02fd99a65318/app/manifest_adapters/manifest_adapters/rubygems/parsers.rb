module ManifestAdapters
  module Rubygems
    module Parsers
      SPECIAL_CHARACTERS  = ".-_".freeze
      GEM_NAME_CHARACTERS = "[A-Za-z0-9#{Regexp.escape(SPECIAL_CHARACTERS)}]+".freeze

      def self.gemfile(contents)
        Gemfile.new(contents)
      end

      def self.gemfile_lock(contents)
        GemfileLock.new(contents)
      end

      def self.gemspec(contents)
        Gemspec.new(contents)
      end

      class Parser < ManifestAdapters::Parsers::Base
        def initialize(contents)
          @contents = contents
        end

        def version
          nil
        end

        private

        attr_reader :contents

        def dependency(package_name:, requirements:, scope: nil, raw_requirements: requirements)
          scope = Types::Scope[(scope.presence || :runtime).to_sym]

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements,
            raw_requirements: raw_requirements,
            scope:        scope,
            malformed:    package_name.blank?,
          )
        end

        def normalize_requirements(dependency)
          dependency.requirement.requirements
            .map { |operator, version| [operator, version.to_s].join(" ") }
            .join(",")
        end

        def malformed?
          parsed.blank?
        end
      end

      class Gemfile < Parser
        GEMSPEC_INDICATOR = /^gemspec/

        def name
          nil
        end

        def package?
          contents.to_s.lines.grep(GEMSPEC_INDICATOR).any?
        end

        def dependencies
          parsed.dependencies.map do |dependency|
            dependency(
              package_name: dependency.name,
              scope:        dependency.type.presence,
              requirements: normalize_requirements(dependency),
            )
          end
        end

        def parsed
          Gemnasium::Parser.gemfile(contents)
        end
      end

      class GemfileLock < Parser
        # Ignore Gemfile.lock files containing git conflicts
        GIT_CONFLICTS = "<<<".freeze

        # Only parse lines from the `GEM` section of the Gemfile.lock
        GEM_SECTION_PATTERN = /^GEM/.freeze

        # Only parse lines that specify the locked gem and version
        INDENTATION_PATTERN = /^\s{4}\w/.freeze

        # Capture gem name and version from a line like `rails (5.0.0)`
        DEPENDENCY_PATTERN = /\A\s*(?<gem>#{GEM_NAME_CHARACTERS}+)\s\((?<version>.+)\)/.freeze

        # Bundler saves platform-specific information about a Gem in the Gemfile.lock file.
        # Since these aren't _actually_ different versions, but instead different distributions of the same verison,
        # we want to strip the metadata off of the end of the version string so that we can correctly compare versions.
        #
        # The ARCHITECTURES and OSES expressions capture the different possible options we could see, based off
        # of RubyGem's platform.rb file: https://github.com/rubygems/rubygems/blob/-/lib/rubygems/platform.rb
        #
        # PLATFORM_PATTERN combines the architectures and OSes and aims to capture all the potential permutations:
        #   aarch64-linux
        #   arm-linux
        #   arm64-linux
        #   armv7-linux
        #   jruby
        #   universal-darwin-8
        #   x64-mingw-ucrt
        #   x86-freebsd
        #   x86-mswin32-80
        #
        PLATFORM_ARCHITECTURES = /(arm((v\S+)|64)?|aarch64|java|jruby|powerpc|sparc|universal|x64|x86|x86_64)/.freeze
        PLATFORM_OSES = /(aix|bitrig|cygwin|dalvik|darwin|dotnet|freebsd|hpux|java|linux(-gnu|-musl)?|macruby|mingw|mingw32|netbsdelf|openbsd|solaris|unknown)/.freeze
        PLATFORM_PATTERN = /-#{PLATFORM_ARCHITECTURES}(-#{PLATFORM_OSES}(-(\d+|ucrt))?)?$/.freeze

        def name
          nil
        end

        def package?
          false
        end

        def dependencies
          parsed.map do |spec|
            requirements = spec[:version].sub(PLATFORM_PATTERN, "")

            dependency(
              package_name: spec[:gem],
              requirements: "= #{requirements}",
              raw_requirements: "= #{spec[:version]}",
              scope: nil
            )
          end
        end

        private

        def parsed
          return [] if conflicts?

          gem_lines.map do |line|
            line.match(DEPENDENCY_PATTERN)
          end.reject(&:blank?)
        end

        def gem_lines
          capture = false
          done = false
          in_gem_section = false
          contents.each_line.lazy.select do |line|
            in_gem_section = true if line.match(GEM_SECTION_PATTERN)
            in_gem_section = false if in_gem_section && line.blank?

            in_gem_section && line.match(INDENTATION_PATTERN)
          end
        end

        def conflicts?
          contents.include?(GIT_CONFLICTS)
        end
      end

      class Gemspec < Parser
        NAME_PATTERN    = /\.name\s*=.*?(((?<!%)#{GEM_NAME_CHARACTERS})+)/
        VERSION_PATTERN = /\.version\s*=.*?(\d[\w\.]+)/

        def name
          contents.match(NAME_PATTERN)&.[](1)
        end

        def version
          contents.match(VERSION_PATTERN)&.[](1)
        end

        def package?
          true
        end

        def dependencies
          parsed.dependencies.map do |dependency|
            dependency(
              package_name: dependency.name,
              scope: dependency.type.presence,
              requirements: normalize_requirements(dependency),
            )
          end
        end

        def parsed
          Gemnasium::Parser.gemspec(contents.to_s)
        end
      end
    end
  end
end
