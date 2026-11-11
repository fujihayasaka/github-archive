# frozen_string_literal: true

FactoryBot.define do
  factory :update_job_error do
    association :update_job
    error_details { { "message" => "My message" } }
    error_type { "dependency_file_not_evaluatable" }
  end
end
