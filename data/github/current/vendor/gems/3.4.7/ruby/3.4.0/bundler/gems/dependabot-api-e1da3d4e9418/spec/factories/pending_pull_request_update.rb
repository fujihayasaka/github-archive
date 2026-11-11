# frozen_string_literal: true

FactoryBot.define do
  factory :pending_pull_request_update do
    association :pull_request
    updated_base_commit_sha { "newbasecommitsha" }
  end
end
