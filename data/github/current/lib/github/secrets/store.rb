# typed: true
# frozen_string_literal: true

module GitHub
  module Secrets
    class Store
      ENV_PERSISTENCE_KEY = "persist_in_env"

      def initialize
        @env = {}
        @secrets = {}
      end

      def from(env:, registry: {})
        @env = env.to_h.dup
        secrets_registry = registry["secrets"]
        if secrets_registry.present?
          keys_to_extract = secrets_registry.keys.reject do |key|
            secrets_registry[key][ENV_PERSISTENCE_KEY]
          end
          @secrets = extract_secrets(env, keys_to_extract)
        else
          @secrets = {}
        end

        self
      end

      def fetch(key, default = nil, &block)
        @secrets[key] || @env[key] || default || block&.call
      end

      def inspect
        "#<#{self.class.name}:#{object_id}>"
      end

      private

      def extract_secrets(environment, keys)
        keys.reduce({}) do |result, key|
          result.merge({ key => environment.delete(key) })
        end
      end
    end
  end
end
