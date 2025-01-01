# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class KV < Platform::Loader
      def self.load(key)
        self.for.load(key)
      end

      def fetch(keys)
        keys.zip(GitHub.kv.mget(keys).value!).to_h # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end
  end
end
