# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::LocalExperimentationConfig
  ParameterType = T.type_alias { T.any(T::Boolean, Integer, Float, String) }
end
