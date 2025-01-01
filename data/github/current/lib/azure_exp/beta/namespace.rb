# typed: true
# frozen_string_literal: true

module AzureEXP::Beta

  class Namespace < T::Struct
    const :name, String
    const :experiments, T::Array[AzureEXP::Beta::Experiment]
  end
end
