# frozen_string_literal: true

FactoryBot.define do
  factory :advisory_sync_state do
    processed_at { nil }
    pushed_at { nil }
    advisory_id { create(:advisory).id }

    trait :failed do
      processed_at { 1.hour.ago }
      pushed_at { nil }
    end

    trait :succeeded do
      processed_at { 1.hour.ago }
      pushed_at { 1.hour.ago }
    end
  end
end
