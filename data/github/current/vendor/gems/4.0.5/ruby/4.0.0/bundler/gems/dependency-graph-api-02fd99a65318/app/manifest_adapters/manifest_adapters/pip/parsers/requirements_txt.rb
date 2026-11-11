module ManifestAdapters
  module Pip
    module Parsers
      class RequirementsTxt < ManifestAdapters::Parsers::Base
        SKIPPABLE_LINE = /^\s*#|\/|^\s*-/

        def initialize(content, filename:, path:)
          @filename = filename
          @path = path
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          return @dependencies if @dependencies

          @dependencies = []

          content.
            each_line.
            grep_v(SKIPPABLE_LINE).
            reject(&:blank?).each do |dep|
              begin
                @dependencies << parse_dependency(dep)
              rescue Pip::DependencyString::ParseError
                # due to the nature of requirements.txt
                # it was decided that should a given line
                # fail to parse, we should simply ignore that
                # line and keep on parsing.
                #
                # however, malformed manifests are thrown out
                # by the `ManifestBackfill` class.
                #
                # Consequently, we can no longer mark
                # requirements.txt files as malformed just because
                # a given line failed to pass.
                #
                # @malformed = true
              end
            end

          @dependencies
        end

        def malformed?
          dependencies
          @malformed
        end

        private

        attr_reader :content, :filename, :path

        def parse_dependency(dependency)
          package_name, requirements = Pip::DependencyString.parse(dependency).values_at(:package_name, :requirements)
          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements.to_s,
            raw_requirements: requirements.to_s,
            scope: scope,
          )
        end

        def scope
          if filename =~ /\btest\b|\btests\b|\bdev\b|\bdevelopment\b/
            Types::Scope[:development]
          else
            Types::Scope[:runtime]
          end
        end
      end
    end
  end
end
