# frozen_string_literal: true

FactoryBot.define do
  factory :update_job_unknown_error do
    association :update_job
    error_details { { "message" => "My message" } }
    error_type { "unknown_error" }
  end
end
