# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :patreon_webhook_event do
    transient do
      sponsors_patreon_user { create(:sponsors_patreon_user) }
      sponsors_patreon_campaign_webhook do
        create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: sponsors_patreon_user)
      end
    end

    kind { 0 } # Unknown
    pending
    payload do
      { "data" => { "relationships" => { "campaign" => {
        "data" => { "id" => sponsors_patreon_campaign_webhook.campaign_id, "type" => "campaign" }
      }, "user" => { "data": { "id" => sponsors_patreon_user.patreon_user_id, "type" => "user" } } } } }
    end
    account_id { sponsors_patreon_user.patreon_user_id }

    trait :pending do
      status { :pending }
      processed_at { nil }
    end

    trait :ignored do
      status { :ignored }
      processed_at { nil }
    end

    trait :processed do
      status { :processed }
      processed_at { Time.now }
    end

    trait :members_create do
      kind { 1 }
    end
  end
end
