# frozen_string_literal: true

module ManifestAdapters
  module Pub
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "pubspec.yaml"
          Types::Manifest[:pubspec_yaml]
        when "pubspec.yml"
          Types::Manifest[:pubspec_yaml]
        when "pubspec.lock"
          Types::Manifest[:pubspec_lock]
        end
      end

      def self.package_manager
        Types::PackageManager[:pub]
      end

      private

      def parsed
        return @parsed if defined?(@parsed)

        @parsed = case manifest_type
          when Types::Manifest[:pubspec_yaml]
            ManifestAdapters::Pub::Parsers::Yaml.new(content)
          when Types::Manifest[:pubspec_lock]
            ManifestAdapters::Pub::Parsers::Lock.new(content)
        end
      end
    end
  end
end
