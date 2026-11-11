# frozen_string_literal: true

module ManifestAdapters
  module Cargo
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "cargo.toml"
          Types::Manifest[:cargo_toml]
        when "cargo.lock"
          Types::Manifest[:cargo_lock]
        end
      end

      def self.package_manager
        Types::PackageManager[:rust]
      end

      private

      def parsed
        return @parsed if defined?(@parsed)

        @parsed = case manifest_type
          when Types::Manifest[:cargo_toml]
            ManifestAdapters::Cargo::Parsers::Toml.new(content)
          when Types::Manifest[:cargo_lock]
            ManifestAdapters::Cargo::Parsers::Lock.new(content)
        end
      end

      # default (passthrough) impl of parse_dependency is fine here b/c @parsed
      # will need to have already built ManifestAdapter::Manifest::Dependency
      # records, in order to capture scope and other fields resolved on the
      # particular type of parent manifest we're parsing (toml or lock)
    end
  end
end
