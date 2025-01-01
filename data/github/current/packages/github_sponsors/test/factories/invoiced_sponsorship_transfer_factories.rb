# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :invoiced_sponsorship_transfer do
    transient do
      sponsorable_login { "invoiced-sponsorable-#{SecureRandom.hex(9)}" }
      sponsor_login { "invoiced-sponsor-#{SecureRandom.hex(11)}" }
      skip_metadata_creation_for_actor { false }
    end
    sponsors_listing do
      create(:sponsors_listing, :approved, :with_stripe_account, sponsorable_login: sponsorable_login)
    end
    sponsor { create(:invoiced_organization, login: sponsor_login) }
    actor { create(:staff_admin_user, :verified, skip_metadata_creation: skip_metadata_creation_for_actor) }
    zuora_payment_id { "2c92a00d6ff0e96f0170168b81415536" }

    # $30,000 annual minimum for Premium Sponsors currently; $30,000 / 12 months = $2,500 monthly:
    amount_in_cents { 2_500_00 }

    before(:create) do |transfer, _|
      transfer.stripe_connect_account ||= transfer.sponsors_listing.active_stripe_account_for_self_or_fiscal_host
    end

    trait :completed do
      sequence :stripe_transfer_id do |_n|
        "tr_#{SecureRandom.hex(12)}"
      end

      transfer_created_at { Time.parse("2020-11-01T12:00:00Z") }

      after(:create) do |transfer|
        sponsorship = transfer.sponsor.sponsorships_as_sponsor
          .with_user_or_org_sponsorable(transfer.sponsorable).first
        expires_at = transfer.expires_at || transfer.created_at + 2.months
        if sponsorship
          tier = create(:sponsors_tier, :invoiced, monthly_price_in_cents: transfer.amount_in_cents,
            sponsors_listing: transfer.sponsors_listing, creator: transfer.sponsor)
          sponsorship.update!(
            paid_at: transfer.transfer_created_at,
            tier: tier,
            invoiced_sponsorship_transfer: transfer,
            expires_at: expires_at,
          )
        else
          create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer, expires_at: expires_at,
            monthly_price_in_cents: transfer.amount_in_cents, paid_at: transfer.transfer_created_at)
        end
      end
    end
  end
end
