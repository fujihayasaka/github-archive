# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :acv_contributor do
    repository
    contributor_email { Sham.email }
    add_attribute(:ignore) { false }
  end
end
