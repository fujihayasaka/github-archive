# typed: true
# frozen_string_literal: true

module Site
  module GlobeHelper
    def local_globe_server_endpoint
      ENV["GLOBE_SERVER_URL"]
    end

    def local_globe_server_enabled?
      return false unless Rails.env.development?

      local_globe_server_endpoint.present?
    end

    def local_globe_javascript_bundle_url
      return unless local_globe_server_endpoint.present?

      "#{local_globe_server_endpoint}/js/main.js"
    end
  end
end
