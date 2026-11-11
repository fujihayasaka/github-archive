# typed: strict
# frozen_string_literal: true

module AzureEXP::Beta::RemoteTreatmentAssignment
  # Structures that represent raw TAS Response
  class TASResponse < T::Struct
    const :assignment_context, String
    const :configs, T::Array[AzureEXP::Beta::RemoteTreatmentAssignment::Config]
  end
end
