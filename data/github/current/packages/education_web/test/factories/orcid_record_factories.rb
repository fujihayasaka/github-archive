# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :orcid_record do
    user
    identifier { "0000-0000-0000-0000" }
  end
end
