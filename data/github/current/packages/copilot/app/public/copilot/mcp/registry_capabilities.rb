# typed: strict
# frozen_string_literal: true

module Copilot
  module Mcp
    class RegistryCapabilities < T::Struct
      const :registry_type, String
      const :required_auth, T::Array[String]
      const :required_context, T::Array[String]

      GITHUB_ENTERPRISE_CAPABILITIES = T.let(
        RegistryCapabilities.new(
          registry_type: "github_enterprise",
          required_auth: ["user_token"],
          required_context: ["repo"]
        ).freeze,
        RegistryCapabilities,
      )

      sig { returns(T::Hash[Symbol, T.any(String, T::Array[String])]) }
      def to_h
        {
          registry_type: registry_type,
          required_auth: required_auth,
          required_context: required_context,
        }
      end
    end
  end
end
