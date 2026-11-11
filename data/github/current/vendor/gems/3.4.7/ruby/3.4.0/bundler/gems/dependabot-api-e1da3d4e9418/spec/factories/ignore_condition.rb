# frozen_string_literal: true

FactoryBot.define do
  factory :ignore_condition do
    association :update_config
    dependency_name { "business" }
    version_requirement { ">= 2.0, < 3" }
    update_types { nil }
    from_config_file { false }

    trait :ignore_patch do
      version_requirement { nil }
      update_types { ["version-update:semver-patch"] }
    end

    trait :ignore_minor do
      version_requirement { nil }
      update_types { ["version-update:semver-minor"] }
    end

    trait :ignore_major do
      version_requirement { nil }
      update_types { ["version-update:semver-major"] }
    end
  end
end
