# frozen_string_literal: true

FactoryBot.define do
  factory :update_job do
    triggered_at { Time.now.utc }
    association :update_config, :rate_limited
    sequence :github_request_id
    metrics_metadata { nil }
    enqueue_scheduled_update_id { nil }
    runner_type { "actions" }

    transient do
      sequence(:hashed_token) { |n| "a-hashed-token-#{n}" }
      sequence(:hashed_credentials_token) { |n| "another-hashed-token-#{n}" }
    end

    trait :version_update do
      command { :version }
      security_updates_only { false }
      github_request_id { nil }
    end

    trait :security_update do
      command { :security }
      security_updates_only { true }
    end

    trait :bump_test do
      update_config do
        repo = Repo.active.find_by(github_id: 88632334)
        update_config = repo.nil? ? nil : repo.update_configs.active.last
        update_config || FactoryBot.build(:update_config, :active, :bump_test)
      end
    end

    trait :security do
      command { :security }
      security_updates_only { true }
    end

    trait :pending

    trait :enqueued do
      after(:create) do |update_job, evaluator|
        update_job.transition_to!(
          :enqueued,
          hashed_token: evaluator.hashed_token,
          hashed_credentials_token: evaluator.hashed_credentials_token,
        )
      end
    end

    trait :expired do
      after(:create) { |update_job| update_job.update(expires_at: 1.hour.ago) }
    end

    trait :processing do
      base_commit_sha { "some-hash" }
      enqueued
      after(:create) { |update_job| update_job.transition_to!(:processing) }
    end

    trait :processed do
      processing
      after(:create) { |update_job| update_job.transition_to!(:processed) }
    end

    trait :processed_with_errors do
      processing
      after(:create) do |job|
        job.transition_to!(
          :processed_with_errors,
          errors: [{ "error-type" => "dependency_file_not_evaluatable" }],
        )
      end
    end

    trait :processed_with_pr_limit_exceeded_error do
      processing
      after(:create) do |job|
        job.transition_to!(
          :processed_with_errors,
          errors: [{ "error-type" => "open_pull_request_limit_exceeded" }],
        )
        job.update_job_errors.create!(error_type: "open_pull_request_limit_exceeded")
      end
    end

    trait :pending_retry do
      processed_with_errors
      after(:create) { |update_job| update_job.transition_to!(:pending_retry) }
    end

    trait :timed_out do
      processing
      after(:create) { |update_job| update_job.transition_to!(:timed_out) }
    end

    trait :cancelled do
      after(:create) { |update_job| update_job.transition_to!(:cancelled) }
    end

    trait :abandoned do
      enqueued
      after(:create) { |update_job| update_job.transition_to!(:abandoned) }
    end

    trait :no_successful_runs do
      after(:create) { |update_job| update_job.transition_to!(:no_successful_runs) }
    end

    trait :manual do
      trigger_type { "manual" }
    end

    trait :scheduled do
      trigger_type { "schedule" }
    end

    trait :on_gh_actions do
      actions_external_id { SecureRandom.uuid }
      actions_workflow_run_id { 9876543210 }
      runner_type { "actions" }
    end
  end
end
