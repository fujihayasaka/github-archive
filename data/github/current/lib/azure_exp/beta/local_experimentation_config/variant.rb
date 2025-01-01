# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  class Variant < T::Struct
    const :name, String
    const :parameters, T::Hash[String, AzureEXP::Beta::LocalExperimentationConfig::ParameterType]
    const :details, T.nilable(String)
  end
end
