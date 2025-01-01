# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    source { AdvisoryDB.sources.sample }
    slack_message_ts
    total_count { 1000 }
    created_count { 0 }
    updated_count { 0 }
    errored_count { 0 }

    trait :started do
      started_at { 1.minute.ago }
      created_count { rand(total_count / 2) }
      updated_count { rand(total_count / 2) }
    end

    trait :finished do
      started
      created_count { total_count / 2 }
      updated_count { total_count - created_count }
      finished_at { 1.second.ago }
    end
  end
end
