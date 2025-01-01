# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module FlamegraphEncryption
      sig { returns(T.nilable(String)) }
      def flamegraph_encryption_key
        return @flamegraph_encryption_key if defined?(@flamegraph_encryption_key)

        env_key = ENV["FLAMEGRAPH_ENCRYPTION_KEY"]
        Kernel.raise RuntimeError.new("FLAMEGRAPH_ENCRYPTION_KEY not set") if env_key.nil?
        @flamegraph_encryption_key = T.let(Base64.decode64(env_key), T.nilable(String))

        @flamegraph_encryption_key
      end

      sig { params(key: String).void }
      def flamegraph_encryption_key=(key)
        @flamegraph_encryption_key = T.let(Base64.decode64(key), T.nilable(String))
      end
    end
  end
  extend Config::FlamegraphEncryption
end
