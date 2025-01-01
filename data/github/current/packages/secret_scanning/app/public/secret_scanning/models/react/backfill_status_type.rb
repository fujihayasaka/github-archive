# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class BackfillStatusType < T::Enum
        enums do
          None = new
          Pending = new
          TerminalError = new
          MaxCandidates = new
        end
      end
    end
  end
end
