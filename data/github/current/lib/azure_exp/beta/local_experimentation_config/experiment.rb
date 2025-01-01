# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  class Experiment < T::Struct
    const :name, String
    const :variants, T::Array[AzureEXP::Beta::LocalExperimentationConfig::Variant]
  end
end
