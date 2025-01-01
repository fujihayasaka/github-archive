# typed: strict
# frozen_string_literal: true

module Alloy
  class Manifest
    class << self
      sig { returns(T.nilable(String)) }
      def filename
        manifest&.fetch("manifest", nil)
      end

      # Not all React apps/partials are included in the Alloy bundle. We can check the manifest to see
      # if a given entry point name is supported, indicating that it has an ssr-entry.ts file and is
      # present in the handler.
      sig { params(name: String).returns(T::Boolean) }
      def entry_supports_ssr?(name)
        supported_entries = manifest&.fetch("ssrNames", nil)

        # If the manifest doesn't have a ssrNames key, we assume all entries are supported
        return true if supported_entries.blank?

        supported_entries.include?(name)
      end

      sig { returns(String) }
      def full_manifest_url
        "#{handler_host}/#{Alloy::Manifest.filename}"
      end

      sig { returns(String) }
      def handler_host
        if Rails.env.development? && !GitHub.load_dev_ui_assets_from_cdn?
          return GitHub.ui_dev_server_enabled? ? "http://github.localhost/webpack-alloy" : "http://github.localhost/assets"
        end

        File.join(GitHub.alloy_asset_host_url, "assets")
      end

      private

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def manifest
        GitHubUI::Manifest.new.alloy_manifest
      end
    end
  end
end
