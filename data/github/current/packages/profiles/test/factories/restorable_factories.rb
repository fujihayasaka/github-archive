# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :restorable do
  end

  factory :restorable_organization_user, class: "Restorable::OrganizationUser" do
    restorable
    organization
    user

    trait :complete do
      after(:build) do |org_user|
        Restorable::TypeState.restorable_types.each_key do |restorable_type|
          org_user.restorable.saved(restorable_type)
        end
      end
    end
  end
end
