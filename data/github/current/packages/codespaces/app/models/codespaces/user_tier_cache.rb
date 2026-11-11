# typed: true
# frozen_string_literal: true

module Codespaces
  class UserTierCache
    EXPIRY_HOURS = 1

    def self.set(user_id:, tier_result:)
      return unless user_id && tier_result

      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::Kv.store.set(
          key(user_id: user_id), tier_result.to_json, expires: EXPIRY_HOURS.hours.from_now
        )
      end
    end

    def self.get(user_id:)
      return unless user_id

      result = Codespaces::Kv.store.get(key(user_id: user_id)).value { nil }

      if result.nil?
        nil
      else
        parsed_result = JSON.parse(result)
        TrustTiers::TierResult.new(parsed_result["tier"], parsed_result["reason"])
      end
    end

    def self.key(user_id:)
      "codespaces:user_tier:v1:#{user_id}"
    end
  end
end
