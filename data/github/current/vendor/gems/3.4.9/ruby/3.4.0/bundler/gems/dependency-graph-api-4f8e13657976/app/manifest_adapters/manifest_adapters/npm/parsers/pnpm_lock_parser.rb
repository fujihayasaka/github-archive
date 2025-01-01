module ManifestAdapters
  module Npm
    module Parsers
      class PnpmLockParser < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
          @malformed = false
        end

        def name; end

        def version; end

        def snapshots_with_dev
          @snapshots_with_dev ||= parsed[:snapshots].select { |dep_path, attribs|
            attribs["dev"] == true
          }
        end

        def dependencies
          @dependencies ||= parsed[:packages].filter_map do |dependency_path, attributes|
            unless skip_package?(dependency_path: dependency_path, attributes: attributes)
              is_dev = attributes["dev"] || !!snapshots_with_dev[dependency_path]
              create_dependency(dependency_path: dependency_path, dev: is_dev)
            end
          end
        end

        def malformed?
          !!@malformed
        end

        def parsed
          return @parsed if defined? @parsed

          @parsed = begin
            manifest_content = YAML.safe_load(@content)

            unless manifest_content.is_a? Hash
              @malformed = true
              raise "Invalid content class #{manifest_content.class}. Expected a Hash"
            end

            @file_version = manifest_content["lockfileVersion"].to_s

            if file_version.nil?
              @malformed = true
              raise "Missing lockfileVersion"
            end

            return {
              packages: manifest_content.fetch("packages", {}),
              snapshots: manifest_content.fetch("snapshots", {}),
            }
          rescue Psych::SyntaxError => e
            DependencyGraph.logger.error("error parsing manifest",
              "gh.dependency_graph.package_manager" => "npm",
              "gh.dependency_graph.manifest.type" => "pnpm_lock",
              "gh.dependency_graph.manifest.is_malformed" => true,
              "exception.type" => e.class.name,
              "exception.message" => e.message,
            )
            {}
          end
        end

        private

        attr_reader :file_version

        # <MatchData "@foo/bar@1.2.3" name: "@foo/bar", version: "1.2.3">
        # <MatchData "foo@1.2.3" name: "foo", version: "1.2.3">
        # <MatchData "foo@1.2.3(bar@1.0.0)" name: "foo", version: "1.2.3">
        V9_DEPENDENCY_PATH_MATCH = /^(?<name>(@[^\/]+\/)?[^@\/]+)@(?<version>[^(\/]+)/

        # <MatchData "/@foo/bar@1.2.3" name: "@foo/bar", version: "1.2.3">
        # <MatchData "/foo@1.2.3" name: "foo", version: "1.2.3">
        # <MatchData "/foo@1.2.3(bar@1.0.0)" name: "foo", version: "1.2.3">
        V6_DEPENDENCY_PATH_MATCH = /(?<name>(@[^\/]+\/)?[^@\/]+)@(?<version>[^(\/]+)/

        # <MatchData "/@foo/bar/1.2.3" name: "@foo/bar", version: "1.2.3">
        # <MatchData "/foo/1.2.3" name: "foo", version: "1.2.3">
        # <MatchData "/foo/1.2.3_bar@1.0.0" name: "foo", version: "1.2.3">
        V5_DEPENDENCY_PATH_MATCH = /(?<name>(@[^\/]+\/)?[^@\/]+)\/(?<version>[^_\/]+)/

        def create_dependency(dependency_path:, dev:)
          dependency_match =  if file_version.starts_with?("9")
                                V9_DEPENDENCY_PATH_MATCH
                              elsif file_version.starts_with?("6")
                                V6_DEPENDENCY_PATH_MATCH
                              elsif file_version.starts_with?("5")
                                V5_DEPENDENCY_PATH_MATCH
                              else
                                raise "Unsupported lockfileVersion #{file_version}"
                              end

          # Capture name and version from dependency_path
          #  ref https://ruby-doc.org/3.2.2/Regexp.html#class-Regexp-label-Named+Captures
          dependency = dependency_match.match(dependency_path)

          package_name = dependency[:name]
          requirements = dependency[:version]

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: ManifestAdapters::Npm::Requirements.new(requirements).normalize,
            raw_requirements: requirements,
            scope: dev == true ? Types::Scope[:development] : Types::Scope[:runtime],
            malformed: is_dependency_malformed?(
              package_name: package_name,
              requirements: requirements,
            )
          )
        end

        # https://github.com/github/dependency-graph/issues/2284#issuecomment-1618197319
        def skip_package?(dependency_path:, attributes:)
          return true if attributes.has_key?("id") || attributes.has_key?("prepare")
          if file_version.starts_with?("9")
            dependency_path.starts_with?("/")
          else
            !dependency_path.starts_with?("/")
          end
        end

        def is_dependency_malformed?(package_name:, requirements:)
          ManifestAdapters::Npm::Parsers.is_dependency_malformed(package_name: package_name, requirements: requirements)
        end
      end
    end
  end
end
