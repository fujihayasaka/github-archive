# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :fraud_flagged_sponsor do
    sponsors_fraud_review
    sponsor { create(:user) }
    matched_current_ip { Faker::Internet.ip_v4_address }

    trait :all_matching do
      matched_historical_ip { Faker::Internet.ip_v4_address }
      matched_current_client_id { "849257819.1526270282" }
      matched_historical_client_id { "1446633495.1403957393" }
      matched_current_ip_region_and_user_agent { "Ontario, CA - #{Faker::Internet.user_agent}" }
    end
  end
end
