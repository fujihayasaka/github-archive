# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    module FakeConfig
      def logger; end

      def set_servers(servers); end

      def options
        {}
      end

      def server_by_key(key); end

      def prefix_key; end
    end
  end
end
