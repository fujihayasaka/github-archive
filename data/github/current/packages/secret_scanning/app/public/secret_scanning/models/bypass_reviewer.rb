# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassReviewer < T::Struct

      const :id, Integer
      const :owner_id, Integer
      const :owner_scope, T.any(Symbol, Integer)
      const :security_configuration_id, T.nilable(Integer)
      const :reviewer_id, Integer
      const :reviewer_type, T.any(Symbol, Integer)
    end
  end
end
