# frozen_string_literal: true

FactoryBot.define do
  factory :dependency_group do
    name { "all-the-things" }
    rules do
      {
        patterns: [
          "*",
        ],
      }
    end
    association :update_config

    trait :active do
      deleted_at { nil }
    end

    trait :deleted do
      deleted_at { Time.now.utc }
    end

    trait :applies_to_security do
      applies_to { DependencyGroup::APPLIES_TO_SECURITY_UPDATES }
    end
  end
end
