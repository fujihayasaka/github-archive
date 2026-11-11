# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class CampaignMetadata < T::Struct
      const :security_campaign_id, Integer
      const :number, Integer
      const :name, String
      const :ends_at, Time
      const :completion_percentage, Integer

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          id: security_campaign_id,
          number: number,
          name: name,
          ends_at: ends_at,
          completion_percentage: completion_percentage
        }
      end
    end
  end
end
