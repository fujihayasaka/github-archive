module ManifestAdapters
  module Go
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "go.mod" then Types::Manifest[:go_mod]
        end
      end

      def self.package_manager
        Types::PackageManager[:go]
      end

      private

      def parsed
        @parsed ||= ManifestAdapters::Go::GoModParser.new(content)
      end
    end
  end
end
