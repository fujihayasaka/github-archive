# frozen_string_literal: true

FactoryBot.define do
  factory :update_config do
    association :repo
    package_manager { "bundler" }
    directory { "/" }
    lockfile_only { false }
    default_labels { ["dependencies"] }
    update_schedule { "daily" }
    update_schedule_day_of_week { "monday" }
    update_schedule_time_of_day { "05:00" }
    update_schedule_cron_expression { "@daily" }
    update_schedule_timezone { "UTC" }
    open_pull_requests_limit { 5 }
    pull_request_branch_name_separator { "/" }
    rebase_strategy { "auto" }
    all_registries { false }
    allowed_updates do
      [
        { dependency_type: "direct", update_type: "all" },
      ]
    end
    multi_ecosystem_config { nil }

    trait :bump_test do
      repo do
        repo = Repo.find_by(github_id: 88632334)
        repo || FactoryBot.build(:repo, :bump_test)
      end
    end

    trait :pending

    trait :rate_limited do
      after(:create) { |uc| uc.transition_to!(:rate_limited) }
    end

    trait :active do
      rate_limited
      after(:create) { |uc| uc.transition_to!(:active) }
    end

    trait :deleted do
      active
      after(:create) { |uc| uc.transition_to!(:deleted) }
    end

    trait :daily

    trait :weekly do
      update_schedule { :weekly }
    end

    trait :monthly do
      update_schedule { :monthly }
    end

    trait :quarterly do
      update_schedule { :quarterly }
    end

    trait :semiannually do
      update_schedule { :semiannually }
    end

    trait :yearly do
      update_schedule { :yearly }
    end

    trait :cron do
      update_schedule { :cron }
    end

    trait :grouped_update do
      after(:build) do |update_config|
        update_config.dependency_groups = FactoryBot.build_list(:dependency_group, 1)
      end
    end

    trait :grouped_security_update do
      after(:build) do |update_config|
        update_config.dependency_groups = FactoryBot.build_list(:dependency_group, 1, :applies_to_security)
      end
    end

    trait :with_cooldown do
      after(:create) do |update_config|
        create(:update_config_cooldown, update_config: update_config)
      end
    end

    trait :with_multi_ecosystem_config do
      association :multi_ecosystem_config
      after(:build) do |update_config|
        update_config.dependency_groups =
          build_list(:dependency_group, 1, name: update_config.multi_ecosystem_config.name)
      end
    end
  end
end
