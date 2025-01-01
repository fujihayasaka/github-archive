# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_listing do
    transient do
      tier_count { 0 }
      one_time_tier_count { 0 }
      repository_tier_count { 0 }
      metadata_traits { [] }
      staff_admin_user { User.find_by(gh_role: "staff") || create(:staff_admin_user) }
      sponsorable_login { "sponsorable-#{SecureRandom.hex(9)}" }

      # Each SponsorsListing should have a SponsorsListingStafftoolsMetadata record, and this is the case in
      # production. So typically we want to generate it as part of generating a listing record from the factory,
      # unless you happen to be creating a listing as part of creating a metadata record factory. Set this to false
      # when you want to omit creating the `.stafftools_metadata` relation for the listing.
      should_create_stafftools_metadata { true }
      banned_by { nil }
      banned_at { nil }
      banned_reason { nil }
    end

    legal_name { Faker::Movies::StarWars.character }
    billing_country { "US" }
    country_of_residence { "US" }
    joined_at { Time.now }
    sponsorable do
      create(:verified_user,
        login: sponsorable_login,
      )
    end
    created_by { sponsorable&.organization? ? sponsorable.admins.first : sponsorable }

    trait :fiscal_host do
      is_fiscal_host { true }
      sponsorable { create(:organization, login: sponsorable_login) }
    end

    trait :open_source_collective do
      fiscal_host
      country_of_residence { "US" }
      billing_country { "US" }

      transient do
        sponsorable_login { SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN }
      end
    end

    trait :with_fiscal_host do
      parent_listing { create(:sponsors_listing, :fiscal_host) }
      fiscally_hosted_project_profile_url { Faker::Internet.url }
    end

    survey do
      if sponsorable&.organization?
        Sponsors::OrganizationWaitlistSurvey.find_or_create_survey
      else
        Sponsors::UserWaitlistSurvey.find_or_create_survey
      end
    end

    before(:create) do |listing|
      # ensure sponsorable always has a verified email, since it is
      # required to sign up for Sponsors
      if listing.contact_email.blank?
        listing.contact_email = if listing.sponsorable.emails.verified.any?
          listing.sponsorable.emails.verified.first
        elsif listing.sponsorable.user?
          listing.sponsorable.primary_user_email.verify!
          listing.sponsorable.primary_user_email
        end
      end
    end

    after(:create) do |listing, evaluator|
      if evaluator.should_create_stafftools_metadata
        create(:sponsors_listing_stafftools_metadata, *evaluator.metadata_traits, sponsors_listing: listing,
          banned_at: evaluator.banned_at, banned_by: evaluator.banned_by, banned_reason: evaluator.banned_reason)
      end

      create_list(:sponsors_tier, evaluator.tier_count, :published, sponsors_listing: listing)
      create_list(:sponsors_tier, evaluator.one_time_tier_count, :published, :one_time,
        sponsors_listing: listing)
      create_list(:sponsors_tier, evaluator.repository_tier_count, :published, :with_repository,
        sponsors_listing: listing)
    end

    trait :waitlisted do
      state { :waitlisted }
    end

    trait :banned do
      state { :banned }
      metadata_traits { [:banned] }
    end

    short_description do
      text = Faker::Company.catch_phrase
      text[0...SponsorsListing::MAX_SHORT_DESCRIPTION_LENGTH]
    end
    full_description do
      text = Faker::Lorem.paragraphs(number: 4).join("\n\n")
      text[0...SponsorsListing::MAX_FULL_DESCRIPTION_LENGTH]
    end

    trait :draft do
      state { :draft }
      accepted_at { Time.now }
    end

    trait :pending_approval do
      state { :pending_approval }
      accepted_at { 1.minute.ago }
    end

    trait :requires_additional_review do
      state { :requires_additional_review }
      accepted_at { 1.minute.ago }
    end

    trait :queued_for_auto_approval do
      state { :queued_for_auto_approval }
      accepted_at { 1.minute.ago }
    end

    trait :approved do
      state { :approved }
      tier_count { 1 }
      accepted_at { 1.hour.ago }
      published_at { Time.now }
    end

    trait :disabled do
      state { :disabled }
    end

    trait :sdn_disabled do
      state { :sdn_disabled }
    end

    trait :ignored do
      metadata_traits { [:ignored] }
    end

    trait :with_customized_sponsorable_profile do
      after(:create) do |listing|
        user = listing.sponsorable
        Profile.find_by(user_id: user.id) || create(:profile, user: user, name: "foo")
      end
    end

    trait :with_tier do
      tier_count { 1 }
    end

    trait :with_tiers do
      tier_count { 2 }
    end

    trait :with_one_time_tier do
      one_time_tier_count { 1 }
    end

    trait :with_one_time_tiers do
      one_time_tier_count { 2 }
    end

    trait :with_repository_tier do
      repository_tier_count { 1 }
    end

    trait :with_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, sponsors_listing: listing, country: listing.country_of_residence,
          billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :with_deleted_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, :deleted, sponsors_listing: listing, country: listing.country_of_residence,
          billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :with_automatic_payout_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, sponsors_listing: listing, payout_interval: "monthly",
          country: listing.country_of_residence, billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :with_w8_or_w9_verified_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, :w8_or_w9_verified, sponsors_listing: listing,
          country: listing.country_of_residence, billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :with_w8_or_w9_requested_but_unverified_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, :w8_or_w9_requested_but_unverified, sponsors_listing: listing,
          country: listing.country_of_residence, billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :with_w8_or_w9_not_requested_stripe_account do
      after(:create) do |listing|
        create(:stripe_connect_account, w8_or_w9_requested_at: nil, sponsors_listing: listing,
          country: listing.country_of_residence, billing_country: listing.billing_country)
        listing.reload
      end
    end

    trait :accepts_marketing_email do
      after(:create) do |listing|
        sponsorable = listing.sponsorable
        create(:newsletter_preference, user: sponsorable)
      end
    end

    trait :completed_payout_probation do
      time = Time.now
      payout_probation_started_at { time }
      payout_probation_ended_at { time }
    end

    trait :on_payout_probation do
      payout_probation_started_at { Time.now }
    end

    trait :exempt_from_payout_probation do
      after(:create) do |listing, _evaluator|
        listing.sponsorable.update!(created_at: (SponsorsListing::MANUAL_PAYOUT_NEW_USER_THRESHOLD + 2.hours).ago)
        now = Time.now
        listing.update!(payout_probation_started_at: now, payout_probation_ended_at: now)
      end
    end

    trait :matchable do
      joined_at { SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days }
      accepted_at { SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE }
    end

    trait :for_org do
      sponsorable { create(:organization, login: sponsorable_login) }
    end

    trait :ready_for_submission do
      draft
      with_tier
      with_w8_or_w9_verified_stripe_account
      with_trade_screening_record
    end

    trait :ready_for_approval do
      pending_approval
      with_tier
      with_w8_or_w9_verified_stripe_account
    end

    trait :ready_for_approval_with_custom_amounts do
      pending_approval
      tier_count { 0 }
      with_w8_or_w9_verified_stripe_account
    end

    trait :ready_for_submission_with_custom_amounts do
      draft
      with_w8_or_w9_verified_stripe_account
      tier_count { 0 }
      with_trade_screening_record
    end

    trait :approved_with_only_custom_amounts do
      state { :approved }
      tier_count { 0 }
      accepted_at { 1.hour.ago }
      published_at { Time.now }
    end

    trait :with_uuids do
      after(:create) do |listing|
        create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: :month)
        create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: :year)
        create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: :one_time)
      end
    end

    trait :spammy do
      tier_count { 1 }
      sponsorable { create(:spammy_user, :verified, login: sponsorable_login) }
      state { :spammy }
    end

    trait :with_trade_screening_record do
      after(:create) do |listing|
        if listing.sponsorable.organization?
          create(:account_screening_profile, :with_org, owner: listing.sponsorable)
        else
          create(:account_screening_profile, owner: listing.sponsorable)
        end
      end
    end

    trait :with_no_hit_sdn_screening do
      after(:create) do |listing|
        create(:account_screening_profile, owner: listing.sponsorable, msft_trade_screening_status: :no_hit)
      end
    end

    trait :with_sdn_screening_restriction do
      after(:create) do |listing|
        create(:account_screening_profile, owner: listing.sponsorable, msft_trade_screening_status: :lic_r)
      end
    end

    trait :trusted do
      after(:create) do |listing|
        listing.sponsorable.update!(created_at: (Sponsors::TrustLevel::NEUTRAL_ACCOUNT_AGE_THRESHOLD + 1.day).ago)
      end
    end

    trait :neutral_trust do
      after(:create) do |listing|
        listing.sponsorable.update!(created_at: (Sponsors::TrustLevel::UNTRUSTED_ACCOUNT_AGE_THRESHOLD + 1.day).ago)
      end
    end

    trait :untrusted do
      after(:create) do |listing|
        listing.sponsorable.update!(created_at: (Sponsors::TrustLevel::UNTRUSTED_ACCOUNT_AGE_THRESHOLD - 1.day).ago)
      end
    end
  end
end
