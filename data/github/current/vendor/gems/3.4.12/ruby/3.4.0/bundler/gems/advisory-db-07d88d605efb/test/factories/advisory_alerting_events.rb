# frozen_string_literal: true

FactoryBot.define do
  factory :advisory_alerting_event do
    ghsa_id
    sequence(:alerting_event_id) { |n| n }
    processed_at { nil }
    finished_at { nil }
    notification_count { 0 }
    alert_count { 0 }

    # Create an advisory with a matching GHSA ID, or use existing
    advisory do
      unless Advisory.exists?(ghsa_id: ghsa_id)
        create(:advisory, ghsa_id: ghsa_id)
      end
    end

    factory :processed_alerting_event do
      processed_at { Time.zone.now }
      finished_at { nil }
      notification_count { 0 }
      alert_count { 0 }
    end

    factory :finished_alerting_event do
      processed_at { 5.minutes.ago }
      finished_at { Time.zone.now }
      notification_count { 3 }
      alert_count { 1 }
    end
  end
end
