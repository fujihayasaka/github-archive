# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module BingIndexnow
      def bing_indexnow_api_key
        @bing_indexnow_api_key ||= ENV.fetch("BING_INDEXNOW_API_KEY")
      end
      attr_writer :bing_indexnow_api_key
    end
  end

  extend Config::BingIndexnow
end
