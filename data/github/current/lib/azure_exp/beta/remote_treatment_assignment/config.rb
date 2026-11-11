# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::RemoteTreatmentAssignment
  # Structures that represent raw TAS Response
  class Config < T::Struct
    const :id, String
    const :parameters, T::Hash[String, AzureEXP::Beta::ParameterType]
  end
end
