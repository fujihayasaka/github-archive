# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    # Implements a factory for ecosystem registers
    class AbstractEcosystemRegister
      extend T::Generic
      extend T::Sig
      abstract!

      # Abstract: Registers must implement their own Registry
      sig { abstract.returns(AbstractEcosystemRegistry) }
      private_class_method def self.registry; end

      # Get all registered ecosystems
      sig { returns(T::Array[AdvisoryDB::Ecosystems::EcosystemV2]) }
      def self.ecosystems
        registry.ecosystems
      end

      # Get an ecosystem from the registry by its slug
      sig do
        params(
          slug: Symbol
        ).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2))
      end
      def self.get(slug)
        registry.get(slug)
      end

      # Add an ecosystem to the registry
      sig do
        params(
          slug: Symbol,
          ecosystem: AdvisoryDB::Ecosystems::EcosystemV2
        ).returns(AdvisoryDB::Ecosystems::EcosystemV2)
      end
      private_class_method def self.add(slug, ecosystem)
        registry.add(slug, ecosystem)
      end
    end
  end
end
