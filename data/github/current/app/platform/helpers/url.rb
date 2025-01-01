# typed: false
# frozen_string_literal: true

module Platform
  module Helpers
    module Url
      # Implement _two_ url-related fields for this object.
      # - "#{prefix}Url", the absolute URL for this resource
      # - "#{prefix}Path", the relative path for this resource.
      #
      # This helper defines one method for each of those fields.
      def url_fields(description:, prefix: nil, visibility: nil, url_suffix: nil, deprecated: nil, null: false, origin: GitHub.url, feature_flag: nil, mobile_only: nil, &get_url_func)
        if description && !description.include?("URL")
          raise ArgumentError, "description must include the string 'URL'." # rubocop:disable GitHub/UsePlatformErrors
        end

        url_method_name = [prefix, "url"].compact.join("_")
        path_method_name = [prefix, "resource_path"].compact.join("_")

        get_url_func ||= begin
          url_suffix ||= "/#{prefix}" if prefix

          if url_suffix
            ->(obj) { obj.async_url(url_suffix) }
          else
            ->(obj) { obj.async_url }
          end
        end

        field(url_method_name, Platform::Scalars::URI, description, null: null, visibility: visibility, deprecated: deprecated, feature_flag: feature_flag, mobile_only: mobile_only)
        define_method(url_method_name) do
          Promise.resolve(get_url_func.call(@object)).then do |uri|
            next unless uri
            full_uri = Addressable::URI.parse(uri)
            # This `origin` is given at boot -- if it was going to fail to parse, it would fail in tests.
            origin = Addressable::URI.parse(origin)
            full_uri.scheme = origin.scheme
            full_uri.host = if GitHub.multi_tenant_enterprise?
              GitHub.host_name_with_tenant
            else
              origin.host
            end
            full_uri.port = origin.port
            full_uri
          end
        end

        path_description = description&.sub("URL", "path")
        field(path_method_name, Platform::Scalars::URI, path_description, null: null, visibility: visibility, deprecated: deprecated, feature_flag: feature_flag, mobile_only: mobile_only)
        define_method(path_method_name) do
          Promise.resolve(get_url_func.call(@object)).then do |uri|
            next unless uri
            path_uri = Addressable::URI.parse(uri)
            path_uri.scheme = nil
            path_uri.host = nil
            path_uri.port = nil
            path_uri
          end
        end
      end
    end
  end
end
