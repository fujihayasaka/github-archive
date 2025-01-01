# typed: true
# frozen_string_literal: true

module AzureEXP::Beta
  class Experiment < T::Struct
    const :name, String
    const :variants, T::Array[AzureEXP::Beta::Variant]
  end
end
