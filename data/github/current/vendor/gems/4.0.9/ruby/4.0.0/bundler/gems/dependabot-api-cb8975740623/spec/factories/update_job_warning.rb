# frozen_string_literal: true

FactoryBot.define do
  factory :update_job_warning do
    association :update_job
    warn_type { "deprecated_method" }
    warn_title { "Deprecated Method Used" }
    warn_description { "This method will be removed in future versions." }
  end
end
