# frozen_string_literal: true

FactoryBot.define do
  factory :cwe do
    cwe_id
    name { "Name of #{cwe_id}" }
  end
end
