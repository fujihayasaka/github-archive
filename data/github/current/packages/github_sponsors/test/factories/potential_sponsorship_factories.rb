# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :potential_sponsorship do
    transient do
      time_zone_name { Sponsors::TimeZone.supported_names.to_a.sample }
    end
    potential_sponsor { create(:organization) }
    potential_sponsorable { create(:user, time_zone_name: time_zone_name) }
    created_by { create(:user, :staff, :verified) }

    trait :pending do
      state { :pending }
    end

    trait :acknowledged do
      state { :acknowledged }
    end

    trait :sponsors_listing_created do
      state { :sponsors_listing_created }

      after(:create) do |potential_sponsorship|
        create(:sponsors_listing, sponsorable: potential_sponsorship.potential_sponsorable)
      end
    end

    trait :ready_for_sponsorship do
      state { :sponsors_listing_created }

      after(:create) do |potential_sponsorship|
        create(:sponsors_listing, :approved, sponsorable: potential_sponsorship.potential_sponsorable)
      end
    end

    trait :sponsorship_created do
      state { :sponsorship_created }

      after(:create) do |potential_sponsorship|
        create(:sponsors_listing, :approved, sponsorable: potential_sponsorship.potential_sponsorable)
        create(:billing_plan_subscription, user: potential_sponsorship.potential_sponsor)
        create(:sponsorship, sponsor: potential_sponsorship.potential_sponsor,
          sponsorable: potential_sponsorship.potential_sponsorable)
      end
    end

    trait :with_profile do
      after(:create) do |potential_sponsorship|
        bio = Faker::TvShows::Spongebob.quote.truncate(Profile::BIO_MAX_LENGTH)
        create(:profile, user: potential_sponsorship.potential_sponsorable, name: Faker::Games::Zelda.character,
          bio: bio)
      end
    end

    trait :with_message do
      message do
        sponsor_name = potential_sponsor&.safe_profile_name || "CompanyName"
        "We're happy to share that #{sponsor_name} wants to sponsor you for $500 a month because they depend on " \
          "something you maintain."
      end
    end
  end
end
