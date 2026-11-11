# frozen_string_literal: true

FactoryBot.define do
  factory :pending_pull_request do
    association :update_job
    updated_dependency_details do
      [{
        "name" => "business",
        "version" => "1.8.0",
        "previous_version" => "1.3.0",
        "requirements" => [],
        "previous_requirements" => [],
        "package_manager" => "bundler",
      }]
    end
    sequence(:sort_key, 1)

    trait :pending

    trait :created do
      after(:create) { |pr| pr.transition_to!(:created) }
    end

    trait :abandoned do
      after(:create) { |pr| pr.transition_to!(:abandoned) }
    end
  end
end
