# typed: strict
# frozen_string_literal: true

module Alloy
  class Manifest
    ASSETS_PATH = "public/assets"
    MANIFEST_PATH = T.let(Rails.root.join(ASSETS_PATH, "manifest.alloy.json"), Pathname)
    @@parsed_manifest = T.let(nil, T.nilable(T::Hash[String, T.untyped]))

    class << self
      sig { returns(T.nilable(String)) }
      def filename
        manifest["manifest"]
      end

      # Not all React apps/partials are included in the Alloy bundle. We can check the manifest to see
      # if a given entry point name is supported, indicating that it has an ssr-entry.ts file and is
      # present in the handler.
      sig { params(name: String).returns(T::Boolean) }
      def entry_supports_ssr?(name)
        supported_entries = manifest["ssrNames"]

        # If the manifest doesn't have a ssrNames key, we assume all entries are supported
        return true if supported_entries.blank?

        supported_entries.include?(name)
      end

      sig { returns(String) }
      def full_manifest_url
        "#{handler_host}/#{Alloy::Manifest.filename}"
      end

      private

      sig { returns(String) }
      def handler_host
        return "http://github.localhost/assets" if Rails.env.development?

        File.join(GitHub.alloy_asset_host_url, "assets")
      end

      # In development, we can update the alloy bundle without restarting the server,
      # so we have to make sure that we're always using the latest version.
      # This is not an issue for prod since the bundle won't change
      sig { returns(T::Hash[String, T.untyped]) }
      def manifest
        return parse_manifest if Rails.env.development?
        return @@parsed_manifest unless @@parsed_manifest.nil?

        @@parsed_manifest = parse_manifest
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parse_manifest
        JSON.parse(File.read(MANIFEST_PATH))
      rescue JSON::ParserError
        {}
      end
    end
  end
end
