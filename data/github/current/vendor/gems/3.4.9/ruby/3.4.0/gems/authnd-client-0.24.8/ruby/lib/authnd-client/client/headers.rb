# frozen_string_literal: true

require "base64"

module Authnd
  module Client
    ENABLED_FEATURES_HEADER = "X-GitHub-Features"
    AUTHND_CUSTOM_HEADER = "X-GitHub-Authnd-Custom-Header"

    # format_enabled_features_header formats the provided list of features for usage in a request header. Any features
    # encoded in the header will be interpretted by the authnd server to drive optional behavior.
    def self.format_enabled_features_for_header(features)
      raise ArgumentError, "enabled features must be a list" unless features.is_a?(Array)

      features.each do |feature|
        raise ArgumentError, "all features be strings" unless feature.is_a?(String)
      end

      Base64.strict_encode64(JSON.dump(features))
    end

    def self.format_custom_header_content(content)
      raise ArgumentError, "content must be a Hash" unless content.is_a?(Hash)

      fragments = []
      content.each do |k, v|
        raise ArgumentError, "key must be string or symbol" unless k.is_a?(String) || k.is_a?(Symbol)
        raise ArgumentError, "value must be primitive" unless v.is_a?(String) || v.is_a?(Numeric) || [true, false].include?(v)

        fragments << "#{k}:#{v}"
      end

      header_string = fragments.join(",")
      Base64.strict_encode64(header_string)
    end
  end
end
