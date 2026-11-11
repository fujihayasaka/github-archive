module ManifestAdapters
  module Actions
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        path, filename = path.to_s, filename.to_s
        # if the filename is already in the path, then we have the full path in `path`
        # if it's not, then we need to join the `path` and `filename` to get the full path
        full_path = if filename == File.basename(path)
                      path
                    else
                      File.join(path, filename)
                    end
        case full_path
        when /\A\.github\/workflows\/[^\/]+\.ya?ml\z/i then Types::Manifest[:workflow_yaml]
        end
      end

      def self.package_manager
        Types::PackageManager[:actions]
      end

      private

      def parsed
        @parsed ||= ManifestAdapters::Actions::Parsers::WorkflowYaml.new(content, private_repository: private_repository?)
      end
    end
  end
end
