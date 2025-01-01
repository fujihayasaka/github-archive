module ManifestAdapters
  module Rubygems
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "gemfile", "gems.rb"          then Types::Manifest[:gemfile]
        when "gemfile.lock", "gems.locked" then Types::Manifest[:gemfile_lock]
        when /\.gemspec\z/                 then Types::Manifest[:gemspec]
        end
      end

      def self.package_manager
        Types::PackageManager[:rubygems]
      end

      private

      def malformed?
        parsed.blank?
      end

      def parsed
        @parsed ||= case manifest_type
        when Types::Manifest[:gemfile]      then ManifestAdapters::Rubygems::Parsers.gemfile(content)
        when Types::Manifest[:gemfile_lock] then ManifestAdapters::Rubygems::Parsers.gemfile_lock(content)
        when Types::Manifest[:gemspec]      then ManifestAdapters::Rubygems::Parsers.gemspec(content)
        end
      end
    end
  end
end
