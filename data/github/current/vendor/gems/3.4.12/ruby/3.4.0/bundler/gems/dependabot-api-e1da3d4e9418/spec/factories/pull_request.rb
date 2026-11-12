# frozen_string_literal: true

FactoryBot.define do
  factory :pull_request do
    association :repo, :active
    update_config do
      repo.update_configs.first || association(:update_config, repo: repo)
    end
    update_job { association :update_job, update_config: update_config }
    multiple_dependencies { dependencies.count > 1 }
    sequence(:github_number, 1001)
    head_commit_sha { "1asdkjh123jk" }
    base_commit_sha { "basecommitsha" }
    dependabot_commit_sha { "1asdkjh123jk" }

    transient do
      dependencies do
        [{
          name: "business",
          version: "1.8.0",
          previous_version: "1.3.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "bundler",
        }]
      end

      hashed_token { nil }
    end

    after(:create) do |pr, evaluator|
      evaluator.dependencies.each do |dep|
        dep = dep.symbolize_keys
        dep = build(
          :updated_dependency,
          pull_request: pr,
          name: dep[:name],
          version: dep[:version],
          previous_version: dep[:previous_version],
          requirements: dep[:requirements],
          previous_requirements: dep[:previous_requirements],
          package_manager:
            dep[:package_manager] || pr.update_config.package_manager,
          removed: dep[:removed] || false,
          directory: dep[:directory] || pr.update_config.directory || pr.update_config.directories.first,
        )
        dep.save!
      end

      next if evaluator.hashed_token.blank?

      pr.hashed_token = evaluator.hashed_token
    end

    trait :bump_test do
      repo do
        Repo.find_by(github_id: 88632334) || association(:repo, :bump_test)
      end
    end

    trait :up_to_date

    trait :updating do
      after(:create) do |pr|
        pr.transition_to!(:updating)
        pr.create_rebase_update_jobs
      end
    end

    trait :merged do
      after(:create) { |pr| pr.transition_to!(:merged) }
    end

    trait :closed do
      after(:create) { |pr| pr.transition_to!(:closed) }
    end

    trait :for_a_grouped_update do
      grouped_update { true }
      association :dependency_group
    end

    trait :for_a_multi_ecosystem_update do
      grouped_update { true }
      update_config { association :update_config, :with_multi_ecosystem_config, repo: }
    end
  end
end
