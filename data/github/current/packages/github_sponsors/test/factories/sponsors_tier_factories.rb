# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_tier do
    transient do
      sponsorable_login { "sponsorable-#{SecureRandom.hex(9)}" }
    end

    sponsors_listing { create(:sponsors_listing, tier_count: 0, sponsorable_login: sponsorable_login) }
    sequence(:monthly_price_in_cents) { |n| n * 1_00 }
    yearly_price_in_cents { monthly_price_in_cents * 12 if monthly_price_in_cents.present? }
    description { "- #{Faker::Company.catch_phrase}\n- #{Faker::Company.catch_phrase}" }

    creator do
      if sponsors_listing&.sponsorable
        sponsorable = sponsors_listing.sponsorable
        if sponsors_listing.for_organization?
          sponsorable.admins.first
        else
          sponsorable
        end
      else
        create(:user, :verified)
      end
    end

    frequency { :recurring }
    name { generate_name }

    trait :draft do
      state { :draft }
    end

    trait :published do
      state { :published }
    end

    trait :retired do
      state { :retired }
    end

    trait :custom do
      state { :custom }
      sponsors_listing { create(:sponsors_listing, :approved, sponsorable_login: sponsorable_login) }
      creator do
        create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      monthly_price_in_cents do
        if sponsors_listing && sponsors_listing.default_tier
          max_tier_cents = sponsors_listing.sponsors_tiers.pluck(:monthly_price_in_cents).max
          max_tier_cents + 1_00
        else
          1_00
        end
      end
      description { "" }
      parent_tier do
        if sponsors_listing
          sponsors_listing.published_sponsors_tiers
            .where(frequency: frequency)
            .monthly_price_in_cents_at_most(monthly_price_in_cents)
            .highest_monthly_price_first
            .first
        end
      end
    end

    trait :invoiced do
      state { :invoiced }
      frequency { :one_time }
      sponsors_listing do
        create(:sponsors_listing, :approved, :with_stripe_account, sponsorable_login: sponsorable_login)
      end
      association :creator, factory: [:invoiced_organization]
    end

    trait :one_time do
      frequency { :one_time }
      yearly_price_in_cents { monthly_price_in_cents }
    end

    trait :with_repository do
      repository do
        sponsorable = sponsors_listing&.sponsorable
        org = if sponsorable&.organization?
          sponsorable
        else
          create(:organization)
        end
        repo = create(:repository, :private, :with_instrumentation, owner: org, created_by_user_id: creator&.id,
          name: "sponsors-only-repo-#{SecureRandom.hex(3)}")
        repo.add_member(sponsorable, action: :admin) if sponsorable&.user?
        repo
      end
      description do
        "- Get access to my secret repository!\n" \
          "- #{Faker::Company.catch_phrase}\n- #{Faker::Company.catch_phrase}"
      end
    end

    trait :with_welcome_message do
      welcome_message { "Welcome new sponsor!" }
    end

    trait :for_org do
      sponsors_listing { create(:sponsors_listing, :approved, :for_org, sponsorable_login: sponsorable_login) }
    end

    trait :approved_sponsors_listing do
      sponsors_listing { create(:sponsors_listing, :approved, tier_count: 0, sponsorable_login: sponsorable_login) }
      state { :published }
    end

    trait :with_uuids do
      after(:create) do |tier|
        zuora_product_id = Faker::Number.hexadecimal(digits: 32)
        create(:billing_product_uuid, :sponsors_tier,
               tier: tier, zuora_product_id: zuora_product_id, billing_cycle: :month)
        create(:billing_product_uuid, :sponsors_tier,
               tier: tier, zuora_product_id: zuora_product_id, billing_cycle: :year)
      end
    end

    trait :exceeds_untrusted_sponsorship_limit do
      monthly_price_in_cents do
        limit_in_cents = Sponsors::TrustSystem::SponsorshipCheck::UNTRUSTED_SPONSORSHIP_LIMIT_IN_DOLLARS * 100
        tier_amounts_in_cents = sponsors_listing.sponsors_tiers.pluck(:monthly_price_in_cents)
        monthly_price_in_cents = (limit_in_cents + 1_00) * 100
        until !tier_amounts_in_cents.include?(monthly_price_in_cents)
          monthly_price_in_cents += 1_00
        end
        monthly_price_in_cents
      end
    end

    trait :skip_max_amount_validation do
      skip_max_amount_validation { true }
    end
  end
end
