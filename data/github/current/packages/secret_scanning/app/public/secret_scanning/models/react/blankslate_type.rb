# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class BlankslateType < T::Enum
        enums do
          Disabled = new
          LoadingFailed = new
        end
      end
    end
  end
end
