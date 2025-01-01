# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_invoiced_agreement_signature do
    association :agreement, factory: [:sponsors_agreement, :invoiced_sponsor]
    organization

    before(:create) do |signature, evaluator|
      if evaluator.organization
        signature.signatory ||= evaluator.organization.admins.first
      end
    end

    trait(:expired) do
      after(:create) do |signature|
        signature.update!(expires_on: 1.week.ago)
      end
    end
  end
end
