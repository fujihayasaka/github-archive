# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassReviewerIdsByType < T::Struct
      const :user_ids, T::Array[Integer]
      const :team_ids, T::Array[Integer]
      const :business_team_ids, T::Array[Integer]
      const :role_ids, T::Array[Integer]
      const :enterprise_role_ids, T::Array[Integer]
    end
  end
end
