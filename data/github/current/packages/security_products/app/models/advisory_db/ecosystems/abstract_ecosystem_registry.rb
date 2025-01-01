# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    # Implements a factory for ecosystem registry singleton instances
    class AbstractEcosystemRegistry
      extend T::Helpers
      abstract!

      # This must come after `abstract!`, otherwise it clobbers Singleton's
      # override of `.new`
      include Singleton

      sig { void }
      def initialize
        @ecosystems = T.let(
          {},
          T::Hash[Symbol, AdvisoryDB::Ecosystems::EcosystemV2]
        )
        @ecosystem_hydro_enum_values = T.let(Set.new, T::Set[Symbol])
        @ecosystem_labels = T.let(Set.new, T::Set[String])
        @ecosystem_names = T.let(Set.new, T::Set[String])
      end

      # Add an ecosystem to the registry
      sig do
        params(
          slug: Symbol,
          ecosystem: AdvisoryDB::Ecosystems::EcosystemV2
        ).returns(AdvisoryDB::Ecosystems::EcosystemV2)
      end
      def add(slug, ecosystem)
        validate_ecosystem!(slug, ecosystem)
        @ecosystems[slug] = ecosystem
        @ecosystem_hydro_enum_values << ecosystem.hydro_enum_value
        @ecosystem_labels << ecosystem.label
        @ecosystem_names << ecosystem.name
        ecosystem
      end

      # Get all registered ecosystems
      sig { returns(T::Array[AdvisoryDB::Ecosystems::EcosystemV2]) }
      def ecosystems
        @ecosystems.values
      end

      # Get an ecosystem from the registry by its slug
      sig do
        params(
          slug: Symbol
        ).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2))
      end
      def get(slug)
        @ecosystems[slug]
      end

      # Reset the registry. ONLY USE FOR TESTING!
      sig { void }
      def reset!
        @ecosystems = {}
        @ecosystem_hydro_enum_values = Set.new
        @ecosystem_labels = Set.new
        @ecosystem_names = Set.new
      end

      # Validate the uniqueness of an ecosystem in the registry
      sig do
        params(
          slug: Symbol,
          ecosystem: AdvisoryDB::Ecosystems::EcosystemV2
        ).void
      end
      private def validate_ecosystem!(slug, ecosystem)
        if @ecosystems.keys.include?(slug)
          raise ArgumentError, "Ecosystem slug is not unique: #{slug}"
        elsif @ecosystem_names.include?(ecosystem.name)
          raise ArgumentError, "Ecosystem name is not unique: #{ecosystem.name}"
        elsif @ecosystem_labels.include?(ecosystem.label)
          raise ArgumentError, "Ecosystem label is not unique: #{ecosystem.label}"
        elsif @ecosystem_hydro_enum_values.include?(ecosystem.hydro_enum_value)
          raise ArgumentError, "Ecosystem Hydro enum value is not unique: #{ecosystem.hydro_enum_value}"
        end
      end
    end
  end
end
