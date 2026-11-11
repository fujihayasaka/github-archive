module ManifestAdapters
  module Maven

    def self.parse_scope(scope)
      # Maven has quite a few scopes and they don't map exactly on the two we have (runtime and test)
      # https://maven.apache.org/pom.html has a list
      # TODO: figure out if we want to support more scopes and if so which ones
      case scope
      when "compile"
        Types::Scope[:runtime]
      when "provided"
        Types::Scope[:runtime]
      when "runtime"
        Types::Scope[:runtime]
      when "test"
        Types::Scope[:development]
      when "system"
        Types::Scope[:runtime]
      when "import"
        Types::Scope[:runtime]
      else
        Types::Scope[:runtime]
      end
    end

    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "pom.xml" then Types::Manifest[:pom_xml]
        end
      end

      def self.package_manager
        Types::PackageManager[:maven]
      end

      private

      def parsed
        @parsed ||= ManifestAdapters::Maven::Parsers::PomXml.new(content)
      end

      def report_errors
        payload = { adapter: :maven,
                    parser: :pom_xml,
                    github_repository_id: github_repository_id,
                    filename: filename,
                    path: path,
                    git_ref: git_ref,
                    pushed_at: pushed_at, }
        Instrument.increment("manifest_adapter.invalid_manifest", **payload)
        DependencyGraph.logger.debug("Invalid manifest: #{payload}",
          "gh.dependency_graph.package_manager" => "maven",
          "gh.dependency_graph.manifest.is_malformed" => true,
          "gh.dependency_graph.manifest_adapter.invalid_payload" => payload,
        )
      end
    end
  end
end
