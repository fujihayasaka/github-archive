# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassPlaceholder < T::Struct
      extend T::Sig

      const :ksuid, String
      const :token_type, String
      const :signature, String
      const :token_metadata, SecretScanning::Models::TokenMetadata
      const :actor_id, Integer
    end
  end
end
