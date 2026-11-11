# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:github_id, 1001)
    github_login { "hmarr" }
    account_type { "user" }
    create_merge_commits { true }
    merge_on_approval { false }
    initial_update_runs_pr_limit { 5 }
    unlimited_private_repos_override { false }
    allow_automerging { true }

    association :tenant, factory: :tenant if Dependabot.proxima?

    transient { sequence(:installation_id, 1001) }

    trait :inactive

    trait :active do
      after(:create) do |account, evaluator|
        account.account_transitions = []
        account.transition_to!(
          :active,
          installation_id: evaluator.installation_id,
        )
      end

      after(:build) do |account, evaluator|
        account.account_transitions.new(
          to_state: :active,
          installation_id: evaluator.installation_id,
          most_recent: true,
        )
        account.account_transitions.proxy_association.loaded!
      end

      after(:stub) do |account, evaluator|
        account.account_transitions.new(
          to_state: :active,
          installation_id: evaluator.installation_id,
          most_recent: true,
        )
        account.account_transitions.proxy_association.loaded!
      end
    end

    trait :user do
      account_type { "user" }
    end

    trait :org do
      account_type { "org" }
    end

    trait :dependabot_fixtures do
      org
      github_login { "dependabot-fixtures" }
      github_id { 44116593 }
      installation_id { 26000 }
    end

    trait :dependabot do
      org
      github_login { "dependabot" }
      github_id { 27347476 }
      installation_id { 25222 }
    end
  end
end
