module ManifestAdapters
  module Composer

    def self.parse_scope(scope)
      case scope
      when :runtime
        Types::Scope[:runtime]
      when :development
        Types::Scope[:development]
      else
        Types::Scope[:runtime]
      end
    end

    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "composer.json" then Types::Manifest[:composer_json]
        when "composer.lock" then Types::Manifest[:composer_lock]
        end
      end

      def self.package_manager
        Types::PackageManager[:composer]
      end

      private

      def parsed
        @parsed ||= case manifest_type
        when Types::Manifest[:composer_json] then ManifestAdapters::Composer::Parsers::ComposerJson.new(content)
        when Types::Manifest[:composer_lock] then ManifestAdapters::Composer::Parsers::ComposerLock.new(content)
        end
      end
    end
  end
end
