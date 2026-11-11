# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  class Config
    sig { returns(T::Array[AzureEXP::Beta::LocalExperimentationConfig::Namespace]) }
    attr_reader :namespaces

    sig { params(namespaces: T::Array[AzureEXP::Beta::LocalExperimentationConfig::Namespace]).void }
    def initialize(namespaces:)
      @namespaces = namespaces
    end

    sig { params(namespace: String).returns(T::Array[AzureEXP::Beta::LocalExperimentationConfig::Experiment]) }
    def experiments_in(namespace:)
      namespace = namespaces.find { |active_namespace| active_namespace.name == namespace }

      return [] if namespace.nil?

      namespace.experiments
    end
  end
end
