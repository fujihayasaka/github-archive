# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_activity do
    sponsorable { create(:user, :sponsorable) }
    sponsor do
      create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
    end
    payment_source { :github }
    action { :new_sponsorship }
    sponsors_tier { low_price_tier }
    repository_id { sponsors_tier&.repository_id }
    timestamp { Time.now }

    transient do
      skip_sponsors_patreon_user_for_sponsor { false }
    end

    trait :org_sponsor do
      sponsor { create(:credit_card_org, plan_subscription: create(:billing_plan_subscription)) }
    end

    trait :org_sponsorable do
      sponsorable { create(:organization, :sponsorable) }
    end

    trait :sponsor_unlinked_from_patreon do
      skip_sponsors_patreon_user_for_sponsor { true }
    end

    trait :patreon do
      payment_source { :patreon }

      after(:create) do |sponsors_activity, evaluator|
        sponsor = sponsors_activity.sponsor
        if !evaluator.skip_sponsors_patreon_user_for_sponsor && sponsor && sponsor.sponsors_patreon_user.nil?
          create(:sponsors_patreon_user, :sponsor, user: sponsor)
          sponsor.reload_sponsors_patreon_user
        end

        sponsorable = sponsors_activity.sponsorable
        if sponsorable && sponsorable.sponsors_patreon_user.nil?
          create(:sponsors_patreon_user, user: sponsorable)
          sponsorable.reload_sponsors_patreon_user
        end
      end
    end

    trait :via_bulk_sponsorship do
      via_bulk_sponsorship { true }
    end

    trait :one_time do
      transient do
        tier_frequency { :one_time }
        monthly_price_in_cents { 3_00 }
      end

      sponsors_tier do
        create(:sponsors_tier, :published, :one_time, sponsors_listing: sponsorable.sponsors_listing,
          monthly_price_in_cents: monthly_price_in_cents)
      end
    end

    transient do
      tier_frequency { :recurring }
      sponsors_listing { sponsorable.sponsors_listing }

      sorted_sponsors_tiers do
        sponsors_tiers = sponsors_listing.published_sponsors_tiers.where(frequency: tier_frequency)

        if sponsors_tiers.empty?
          create(:sponsors_tier, :published, frequency: tier_frequency, sponsors_listing: sponsors_listing,
            monthly_price_in_cents: 1_00)
          create(:sponsors_tier, :published, frequency: tier_frequency, sponsors_listing: sponsors_listing,
            monthly_price_in_cents: 2_00)
        elsif sponsors_tiers.count == 1
          tier1 = sponsors_tiers.first
          tier2_price = tier1.monthly_price_in_cents * 2
          create(:sponsors_tier, :published, frequency: tier1.frequency, sponsors_listing: sponsors_listing,
            monthly_price_in_cents: tier2_price)
        end

        sponsors_listing.published_sponsors_tiers.where(frequency: tier_frequency).order(:monthly_price_in_cents)
      end

      low_price_tier { sorted_sponsors_tiers.first }
      high_price_tier { sorted_sponsors_tiers.second }
    end
  end

  trait :new_sponsorship do
    action { :new_sponsorship }
  end

  trait :cancelled_sponsorship do
    action { :cancelled_sponsorship }
  end

  trait :refund do
    action { :refund }
  end

  trait :upgrade do
    action { :tier_change }
    sponsors_tier { high_price_tier }
    old_sponsors_tier { low_price_tier }
    old_repository_id { old_sponsors_tier&.repository_id }
  end

  trait :downgrade do
    action { :tier_change }
    sponsors_tier { low_price_tier }
    old_sponsors_tier { high_price_tier }
    old_repository_id { old_sponsors_tier&.repository_id }
  end

  trait :pending_upgrade do
    action { :pending_change }
    sponsors_tier { high_price_tier }
    old_sponsors_tier { low_price_tier }
    old_repository_id { old_sponsors_tier&.repository_id }
  end

  trait :pending_downgrade do
    action { :pending_change }
    sponsors_tier { low_price_tier }
    old_sponsors_tier { high_price_tier }
    old_repository_id { old_sponsors_tier&.repository_id }
  end

  trait :pending_cancellation do
    action { :pending_change }
    sponsors_tier { nil }
    old_sponsors_tier { low_price_tier }
    old_repository_id { old_sponsors_tier&.repository_id }
  end

  trait :sponsor_match_disabled do
    action { :sponsor_match_disabled }
    sponsors_tier { low_price_tier }
  end

  trait :processing do
    action { :new_sponsorship }
    timestamp { 1.day.ago }
  end

  trait :with_public_sponsorship do
    after(:create) do |activity|
      create(:sponsorship, :public,
        sponsor: activity.sponsor,
        sponsorable: activity.sponsorable,
      )
    end
  end

  trait :with_private_sponsorship do
    after(:create) do |activity|
      create(:sponsorship, :private,
        sponsor: activity.sponsor,
        sponsorable: activity.sponsorable,
      )
    end
  end
end
