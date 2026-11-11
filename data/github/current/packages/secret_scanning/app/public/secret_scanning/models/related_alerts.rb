# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class RelatedAlerts < T::Struct
      class RelatedAlert < T::Struct
        const :repository_id, Integer
        const :repository_owner, String
        const :repository_name, String
        const :repository_visibility, String
        const :repository_icon, String
        const :number, Integer
        const :token_type, String
      end

      const :alerts, T::Array[RelatedAlert]
      const :more_exist, T::Boolean
    end
  end
end
