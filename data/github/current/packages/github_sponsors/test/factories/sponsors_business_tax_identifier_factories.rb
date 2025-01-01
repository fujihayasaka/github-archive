# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_business_tax_identifier do
    user { create(:organization) }
    country { "US" }
    region { "US-TN" }
  end
end
