# typed: true
# frozen_string_literal: true

module AzureEXP::Beta
  extend T::Sig

  class Variant < T::Struct
    const :name, String
    const :parameters, T::Hash[String, AzureEXP::Beta::ParameterType]
    const :assignment_state, AzureEXP::Beta::AssignmentState
    const :details, T.nilable(String)
  end
end
