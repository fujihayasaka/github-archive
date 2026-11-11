# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  class Namespace < T::Struct
    const :name, String
    const :experiments, T::Array[AzureEXP::Beta::LocalExperimentationConfig::Experiment]
  end
end
