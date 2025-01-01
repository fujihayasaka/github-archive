# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassRequestStatusCountMetric < T::Struct
      const :count, Integer, default: 0
      const :percent, Integer, default: 0
      const :bypass_request_status, T.any(Symbol, Integer), default: 0
    end
  end
end
