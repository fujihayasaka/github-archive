# frozen_string_literal: true

FactoryBot.define do
  factory :suggested_fix do
    association :autofix_suggestion_job

    ai_version { "1.0.0" }
    ai_model { "fake_ai_model" }
    description { "This is a suggested fix" }

    transient do
      dependency_metadata_count { 1 }
    end
    dependency_metadata do
      Array.new(dependency_metadata_count) do
        { "name": Faker::App.name, "version": Faker::App.semantic_version }
      end.to_json
    end

    review_status { :unreviewed }

    trait :with_suggested_fix_files do
      transient do
        files_count { 1 }
      end

      after(:create) do |suggested_fix, evaluator|
        create_list(:suggested_fix_file, evaluator.files_count, suggested_fix: suggested_fix)
        suggested_fix.reload
      end
    end
  end
end
