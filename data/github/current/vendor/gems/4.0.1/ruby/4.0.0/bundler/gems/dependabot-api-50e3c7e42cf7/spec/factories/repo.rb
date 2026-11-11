# frozen_string_literal: true

require "base64"

FactoryBot.define do
  factory :repo do
    association :account, :active
    sequence(:github_id, 3001)
    name { "business" }
    fork { false }
    private { true }
    primary_language { "ruby" }
    default_branch { "master" }
    unreliable_test_suite { false }
    has_ci { true }
    security_updates_enabled { nil }

    trait :bump_test do
      name { "bump-test" }
      github_id { 88632334 }
      fork { false }
      private { true }

      account do
        dependabot = Account.find_by(github_login: "dependabot")
        dependabot || create(:account, :active, :dependabot)
      end
    end

    trait :business do
      name { "business" }
      github_id { 77632112 }
      fork { false }
      private { true }

      account do
        dependabot = Account.find_by(github_login: "dependabot")
        dependabot || create(:account, :active, :dependabot)
      end
    end

    trait :dummy2 do
      name { "dummy-2" }
      github_id { 157422299 }
      fork { false }
      private { false }

      account do
        org = Account.find_by(github_login: "dependabot-fixtures")
        org || create(:account, :active, :dependabot_fixtures)
      end
    end

    trait :with_config_file do
      config_file_path { ".github/dependabot.yml" }
    end

    trait :inactive

    trait :active do
      after(:create) do |repo|
        update_config =
          repo.update_configs.active.
          create_with(update_schedule: "daily").
          find_or_create_by!(
            package_manager: "bundler",
            directory: "/",
            lockfile_only: false,
            default_labels: ["dependencies"],
            allowed_updates: [{
              update_type: "all",
              dependency_type: "direct",
            }],
            update_schedule_time_of_day: "05:00",
            update_schedule_day_of_week: "monday",
            update_schedule_cron_expression: nil,
            update_schedule_timezone: "UTC",
            pull_request_branch_name_separator: "/",
            open_pull_requests_limit:
              UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT,
            rebase_strategy: "auto"
          )

        update_config.transition_to(:rate_limited)
      end
    end

    trait :public do
      private { false }
    end

    trait :no_pause_planned do
      will_pause_at { nil }
      paused_at     { nil }
    end

    trait :will_pause_later do
      will_pause_at { 1.hour.from_now }
      paused_at     { nil }
    end

    trait :currently_paused do
      will_pause_at { 1.minute.ago }
      paused_at     { 1.minute.ago }
    end

    trait :automated_security_updates do
      security_updates_enabled { true }
    end

    trait :manual_security_updates do
      security_updates_enabled { false }
    end
  end

  trait :security_updates_only do
    after(:create) do |repo|
      update_config =
        repo.update_configs.active.
        create_with(update_schedule: "never").
        find_or_create_by!(
          package_manager: "bundler",
          directory: "/",
          lockfile_only: false,
          default_labels: ["dependencies"],
          allowed_updates: [
            { "dependency_type" => "direct", "update_type" => "all" },
            { "dependency_type" => "indirect", "update_type" => "security" },
          ],
          update_schedule_time_of_day: "05:00",
          update_schedule_day_of_week: "monday",
          update_schedule_timezone: "UTC",
          pull_request_branch_name_separator: "/",
          open_pull_requests_limit: UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT,
          rebase_strategy: "auto"
        )

      update_config.transition_to!(:rate_limited)
    end
  end
end
