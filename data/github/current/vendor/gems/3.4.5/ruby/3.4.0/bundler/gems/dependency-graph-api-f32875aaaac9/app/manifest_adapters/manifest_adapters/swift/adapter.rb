module ManifestAdapters
  module Swift
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip
        when "Package.resolved" then Types::Manifest[:package_resolved]
        end
      end

      def self.package_manager
        Types::PackageManager[:swift]
      end

      private

      def parsed
        @parsed ||= ManifestAdapters::Swift::Parsers::PackageResolved.new(content)
      end
    end
  end
end
