module ManifestAdapters
  module Swift
    module Parsers
      class PackageResolved < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
          @malformed = false
        end

        def name; end

        def version; end

        def malformed?
          @malformed
        end

        def dependencies
          return @dependencies if defined?(@dependencies)

          set_version_opts

          @dependencies = pins&.map do |pin|
            source = pin.dig(pin_source).strip
            Pin.new(pin: pin, source: source).to_dependency
          end
        end

        private
        attr_reader :content, :pins, :pin_source

        def parsed
          @parsed ||= begin
            parsed = JSON.parse(content)
            unless parsed.is_a?(Hash)
              DependencyGraph.logger.info("Invalid manifest contents format",
                "gh.dependency_graph.manifest.type" => "swift",
                "gh.dependency_graph.manifest.format" => parsed.class,
              )
              @malformed = true
              {}
            end
            parsed
          rescue JSON::ParserError => e
            DependencyGraph.logger.info("Error parsing manifest",
              "exception.message" => e.message,
              "exception.type" => e.class.name,
              "gh.dependency_graph.manifest.type" => "swift",
            )
            @malformed = true
            {}
          end
        end

        def set_version_opts
          case parsed.dig("version")
          when 1
            @pins = parsed.dig("object", "pins")
            @pin_source = "repositoryURL"
          when 2
            @pins = parsed.dig("pins")
            @pin_source = "location"
          else
            DependencyGraph.logger.info("missing / unknown manifest version",
              "gh.dependency_graph.manifest.type" => "swift",
              "gh.dependency_graph.manifest.version" => parsed.dig("version")
            )
            @malformed = true
          end
        end

        class Pin
          def initialize(pin:, source:)
            @pin    = pin
            @source = source
          end

          def to_dependency
            ManifestAdapters::Manifest::Dependency.new(
              package_name: normalized_package_name,
              requirements: normalized_requirement,
              raw_requirements: version || revision,
              scope: Types::Scope[:runtime],
              malformed: malformed?
            )
          end

          private
          attr_reader :pin

          SCP_PREFIX = /^(ssh:\/\/)?git@/i

          def version
            pin.dig("state", "version")
          end

          def revision
            pin.dig("state", "revision")
          end

          def malformed?
            !valid_package_name? || !valid_requirement?
          end

          def valid_requirement?
            return true if version.blank? # packages with missing versions are valid & treated as >= 0
            version.match?(Versioning::VersionParser::SEMANTIC_PATTERN)
          end

          def normalized_requirement
            return version unless valid_requirement?

            return ">= 0" if version.blank?
            "= #{version}"
          end

          def source
            if @source.start_with?(SCP_PREFIX)
              # convert scp style git urls to http
              return @source.sub(SCP_PREFIX, "http://").sub(/(.*\K\:)/, "/")
            end
            @source
          end

          def valid_package_name?
            !!(source =~ /\A#{URI::regexp}\z/)
          end

          def normalized_package_name
            return source unless valid_package_name?

            uri = URI.parse(source.downcase)
            "#{uri&.host}#{uri&.path}".sub(/\Awww\./, "").sub(/\.git\z/, "")
          end

        end
      end
    end
  end
end
