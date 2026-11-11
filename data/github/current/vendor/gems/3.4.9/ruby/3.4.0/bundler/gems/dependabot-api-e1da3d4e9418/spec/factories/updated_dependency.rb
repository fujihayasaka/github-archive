# frozen_string_literal: true

FactoryBot.define do
  factory :updated_dependency do
    association :pull_request
    name { "business" }
    version { "1.8.0" }
    previous_version { "1.3.0" }
    requirements { [] }
    previous_requirements { [] }
    package_manager { "bundler" }
  end
end
