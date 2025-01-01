require "yarnlock"

module ManifestAdapters
  module Npm
    module Parsers
      MAX_NPM_PACKAGE_NAME_LENGTH=214

      def self.package_json(contents)
        PackageJsonParser.new(contents)
      end

      def self.package_json_lock(contents)
        PackageJsonLockParser.new(contents)
      end

      def self.yarn_lock(contents)
        if contents.include? "__metadata:"
          YarnLockParserV2.new(contents)
        else
          YarnLockParser.new(contents)
        end
      end

      def self.pnpm_lock(contents)
        PnpmLockParser.new(contents)
      end

      def self.is_dependency_malformed(package_name:, requirements:)
        # package name must be a string.
        return true unless package_name.is_a? String

        # if requirements is any string, its a valid package reference.
        return true unless requirements.is_a? String

        # package names cannot be blank
        return true if package_name.blank?

        # npm package names can only have 214 characters
        return true if package_name.length >= MAX_NPM_PACKAGE_NAME_LENGTH

        return false
      end
    end
  end
end
