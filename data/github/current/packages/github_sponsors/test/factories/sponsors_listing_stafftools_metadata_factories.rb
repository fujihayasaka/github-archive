# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_listing_stafftools_metadata do
    transient do
      staff_admin_user { User.find_by(gh_role: "staff") || create(:staff_admin_user) }
    end

    sponsors_listing { create(:sponsors_listing, should_create_stafftools_metadata: false) }
    sponsorable_created_at { sponsors_listing.sponsorable.created_at || Time.now }
    reviewed_at { sponsors_listing.waitlisted? ? nil : Time.now }
    approval_requested_at do
      if sponsors_listing.pending_approval? || sponsors_listing.approved?
        Time.now
      end
    end

    trait :ignored do
      ignored_at { 2.days.ago }
    end

    trait :banned do
      banned_at { Time.now }
      banned_by { staff_admin_user }
      banned_reason { "ETOOMANYSHENANIGANS" }
    end

    trait :with_supported_time_zone do
      transient do
        time_zone_name { Sponsors::TimeZone.supported_names.first }
      end

      after(:create) do |metadata, evaluator|
        metadata.sponsorable.update!(time_zone_name: evaluator.time_zone_name)
      end
    end

    trait :with_time_zone do
      with_supported_time_zone
    end

    trait :with_unsupported_time_zone do
      transient do
        time_zone_name do
          unsupported_country_code = Billing::StripeConnect::Account.unsupported_countries.first
          country_zone = ActiveSupport::TimeZone.country_zones(unsupported_country_code).first
          country_zone.name
        end
      end

      after(:create) do |metadata, evaluator|
        metadata.sponsorable.update!(time_zone_name: evaluator.time_zone_name)
      end
    end

    trait :has_customized_user_profile do
      has_customized_user_profile { true }

      after(:create) do |metadata|
        create(:profile, user: metadata.sponsorable, name: "Sample User", bio: "I love houseplants")
      end
    end

    trait :with_public_non_fork_repository do
      has_public_non_fork_repository { true }

      after(:create) do |metadata|
        create(:repository, :full_creation, owner: metadata.sponsorable)
      end
    end
  end
end
