# frozen_string_literal: true

FactoryBot.define do
  factory :reference do
    advisory
    url

    before(:create) do |reference|
      reference.index ||= reference.advisory.references.count
    end
  end
end
