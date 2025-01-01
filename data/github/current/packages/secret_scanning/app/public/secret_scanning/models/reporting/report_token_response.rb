# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module Reporting
      class ReportTokenResponse < T::Struct
        const :validation, T.nilable(SecretScanning::Models::OnDemandValidation), default: nil
        const :result, T.any(Symbol, Integer), default: :UNKNOWN
      end
    end
  end
end
