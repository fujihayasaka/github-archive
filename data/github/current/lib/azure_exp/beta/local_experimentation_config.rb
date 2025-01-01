# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta
  module LocalExperimentationConfig
    extend T::Sig

    CONFIG_FILE_PATH = T.let("#{Rails.root}/config/experiment_config.json", String)

    sig { returns(AzureEXP::Beta::LocalExperimentationConfig::Config) }
    def self.config
      AzureEXP::Beta::LocalExperimentationConfig::Parser.parse(AzureEXP::Beta::LocalExperimentationConfig.experiment_config_hash)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.experiment_config_hash
      JSON.parse(File.read(AzureEXP::Beta::LocalExperimentationConfig::CONFIG_FILE_PATH), symbolize_names: true).freeze
    end
  end
end
