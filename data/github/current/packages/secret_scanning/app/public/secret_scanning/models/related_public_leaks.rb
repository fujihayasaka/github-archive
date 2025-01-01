# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class RelatedPublicLeaks < T::Struct
      class RelatedPublicLeak < T::Struct
        const :repository_id, Integer
        const :repository_owner, String
        const :repository_name, String
        const :location, T::Hash[T.untyped, T.untyped]
      end

      const :leaks, T::Array[RelatedPublicLeak]
      const :more_exist, T::Boolean
    end
  end
end
