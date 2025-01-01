# typed: strict
# frozen_string_literal: true

module DependencyGraph
  module Ecosystems

    SUPPORTED = T.let(AdvisoryDB::Ecosystems::EcosystemRegister.ecosystems.select(&:dependency_graph_supported?).freeze, T::Array[AdvisoryDB::Ecosystems::EcosystemV2])

    SUPPORTED_LABELS = T.let(SUPPORTED.collect(&:label).freeze, T::Array[String])
    private_constant :SUPPORTED_LABELS

    # Inverse index of ecosystems by label
    SUPPORTED_BY_LABELS = T.let(
      SUPPORTED.each.with_object({}) do |ecosystem, memo|
        memo[ecosystem.label] = ecosystem
      end.freeze,
      T::Hash[String, AdvisoryDB::Ecosystems::EcosystemV2]
    )
    private_constant :SUPPORTED_BY_LABELS

    # TODO: FF dependency_graph_snapshot_arbitrary_ecosystems cleanup
    # We only need one of the below labels. Change UNKNOWN_LABEL to "other"
    UNKNOWN_LABEL = T.let("unknown".freeze, String)
    OTHER_LABEL = T.let("other".freeze, String)

    PACKAGE_MANAGER_MAPPING = T.let({
      PACKAGE_MANAGER_RUBYGEMS: AdvisoryDB::Ecosystems::EcosystemRegister.get(:RUBYGEMS),
      PACKAGE_MANAGER_NPM: AdvisoryDB::Ecosystems::EcosystemRegister.get(:NPM),
      PACKAGE_MANAGER_PIP: AdvisoryDB::Ecosystems::EcosystemRegister.get(:PIP),
      PACKAGE_MANAGER_MAVEN: AdvisoryDB::Ecosystems::EcosystemRegister.get(:MAVEN),
      PACKAGE_MANAGER_NUGET: AdvisoryDB::Ecosystems::EcosystemRegister.get(:NUGET),
      PACKAGE_MANAGER_COMPOSER: AdvisoryDB::Ecosystems::EcosystemRegister.get(:COMPOSER),
      PACKAGE_MANAGER_GOMOD: AdvisoryDB::Ecosystems::EcosystemRegister.get(:GO),
      PACKAGE_MANAGER_RUST: AdvisoryDB::Ecosystems::EcosystemRegister.get(:RUST),
      PACKAGE_MANAGER_ACTIONS: AdvisoryDB::Ecosystems::EcosystemRegister.get(:ACTIONS),
      PACKAGE_MANAGER_PUB: AdvisoryDB::Ecosystems::EcosystemRegister.get(:PUB),
      PACKAGE_MANAGER_SWIFT: AdvisoryDB::Ecosystems::EcosystemRegister.get(:SWIFT),
    }.freeze, T::Hash[Symbol, AdvisoryDB::Ecosystems::EcosystemV2])

    # Return the label for an ecosystem given the package manager symbol
    # TODO: FF dependency_graph_snapshot_arbitrary_ecosystems cleanup
    # remove the ds_arbitary_ecosystems_enabled param
    # Func only needs to be `PACKAGE_MANAGER_MAPPING[key]&.label || UNKNOWN_LABEL`
    sig { params(key: Symbol, ds_arbitrary_ecosystems_enabled: T::Boolean).returns(T.nilable(String)) }
    def self.label(key, ds_arbitrary_ecosystems_enabled: false)
      supported_label = PACKAGE_MANAGER_MAPPING[key]&.label
      return supported_label if supported_label

      ds_arbitrary_ecosystems_enabled ? OTHER_LABEL : UNKNOWN_LABEL
    end

    # Return the label for an ecosystem given the package manager symbol
    sig { params(label: String).returns(T.nilable(AdvisoryDB::Ecosystems::EcosystemV2)) }
    def self.by_label(label)
      SUPPORTED_BY_LABELS[label]
    end

    # Return the package manager symbol for an ecosystem given the label
    sig { params(label: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.label_to_symbol(label)
      if [UNKNOWN_LABEL, OTHER_LABEL].include?(label)
        return :PACKAGE_MANAGER_UNKNOWN
      end

      PACKAGE_MANAGER_MAPPING.each do |key, ecosystem|
        return key if ecosystem.label == label
      end
      nil
    end

    # Returns a list of supported ecosystem labels
    sig { returns(T::Array[String]) }
    def self.supported_labels
      SUPPORTED_LABELS
    end
  end
end
