# frozen_string_literal: true

module ManifestAdapters
  module Nuget

    def self.parse_include(scope)
      # https://docs.microsoft.com/en-us/nuget/reference/nuspec#dependencies-element outlines the include/exclude tag
      # TODO: ensure these scopes are correct and add more?
      if scope.blank?
        Types::Scope[:runtime]
      else
        if scope.include?("runtime")
          Types::Scope[:runtime]
        else
          Types::Scope[:development]
        end
      end
    end

    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        return Types::Manifest[:msbuild] if filename.to_s.strip.downcase.match?("\.(?:csproj)$")
        return Types::Manifest[:msbuild] if filename.to_s.strip.downcase.match?("\.(?:vbproj)$")
        return Types::Manifest[:msbuild] if filename.to_s.strip.downcase.match?("\.(?:vcxproj)$")
        return Types::Manifest[:msbuild] if filename.to_s.strip.downcase.match?("\.(?:fsproj)$")
        return Types::Manifest[:package_config] if filename.to_s.strip.downcase == "packages.config"
        Types::Manifest[:nuspec] if filename.to_s.strip.downcase.match?("\.(?:nuspec)$")
      end

      def self.package_manager
        Types::PackageManager[:nuget]
      end

      private

      def parsed
        @parsed ||= case manifest_type
                    when Types::Manifest[:nuspec] then ManifestAdapters::Nuget::Parsers::Nuspec.new(content)
                    when Types::Manifest[:msbuild] then ManifestAdapters::Nuget::Parsers::Project.new(filename, content)
                    when Types::Manifest[:package_config] then ManifestAdapters::Nuget::Parsers::PackageConfig.new(content)
        end
      end
    end
  end
end
