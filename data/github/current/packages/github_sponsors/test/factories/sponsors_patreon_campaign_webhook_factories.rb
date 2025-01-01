# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_patreon_campaign_webhook do
    sponsors_patreon_user
    sequence(:campaign_id) { |n| n.to_s }
    sequence(:webhook_id) { |n| n.to_s }
    triggers do
      ["members:create", "members:delete", "members:pledge:create", "members:pledge:delete", "members:pledge:update",
       "members:update"]
    end
    secret { SecureRandom.hex(32) }
  end
end
