# typed: true
# frozen_string_literal: true

require "contentful"

module Site
  module Contentful
    class Client < ::Contentful::Client
      def initialize(given_config = {})
        @given_config = given_config
        raise_misconfigured_error if missing_configs.any?

        super(@given_config.merge(config_overrides))
      end

      private

      def config_overrides
        {
          dynamic_entries: dynamic_entries,
          raise_errors: true,
          raise_for_empty_fields: false
        }
      end

      def dynamic_entries
        return :auto if GitHub.contentful_force_auto_dynamic_entries?

        ::Contentful::ContentTypeCache.cache.has_key?(@given_config[:space]) ? :manual : :auto
      end

      def required_configs
        %i[space environment access_token]
      end

      def missing_configs
        required_configs.reject { |k| @given_config[k].present? }
      end

      def raise_misconfigured_error
        raise MisconfiguredClient, "Missing Contentful configuration: #{missing_configs.join(", ")}"
      end

      class MisconfiguredClient < StandardError; end
    end
  end
end
