# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDependencyForSponsorsTierTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @published_tier = create(:sponsors_tier, :published)
    @one_time_tier = create(:sponsors_tier, :published, :one_time)
    @invoiced_tier = create(:sponsors_tier, :invoiced)
  end

  context "#locked_sponsorship?" do
    test "returns false for a recurring tier" do
      refute @published_tier.locked_sponsorship?(active: true, selected_at: 1.second.ago)
    end

    test "returns true for a recently chosen one-time tier" do
      assert @one_time_tier.locked_sponsorship?(active: true, selected_at: 1.second.ago)
    end

    test "returns false for an inactive recently chosen one-time tier" do
      refute @one_time_tier.locked_sponsorship?(active: false, selected_at: 1.second.ago)
    end

    test "returns false for a one-time tier chosen several days ago" do
      refute @one_time_tier.locked_sponsorship?(active: true, selected_at: 3.days.ago)
    end

    test "returns false for a recently chosen invoiced tier" do
      refute @invoiced_tier.locked_sponsorship?(active: true, selected_at: 1.second.ago)
    end
  end

  context "#zuora_id" do
    test "grabs the zuora id from the product uuid record" do
      tier = create(:sponsors_tier)
      Billing::ProductUUID.destroy_all
      create(
        :billing_product_uuid,
        product_type: SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE,
        product_key: tier.id.to_s,
        billing_cycle: "month",
        zuora_product_rate_plan_id: "123abc",
      )

      assert_equal "123abc", tier.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN)
    end
  end

  context "#matches_invoice_item?" do
    test "false if the listing doesn't exist" do
      invoice_item = Billing::Zuora::InvoiceItem.new(
        "chargeName" => "Not a matching charge name",
      )

      @published_tier.listing.delete
      assert_nil @published_tier.reload.listing

      refute @published_tier.matches_invoice_item?(invoice_item)
    end

    context "tier-based Zuora charges" do
      test "false if charge_name does not match listing's slug" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeName" => "Not a matching charge name",
        )
        refute @published_tier.matches_invoice_item?(invoice_item)
      end

      test "true if charge_name contains listing's slug" do
        listing_slug = @published_tier.listing.slug
        tier_name = @published_tier.name
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeName" => "#{listing_slug}: #{tier_name} - month",
        )
        assert @published_tier.matches_invoice_item?(invoice_item)
      end
    end

    context "listing-based Zuora charges" do
      test "false if charge_name does not match listing's zuora_slug" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "unitPrice"  => @published_tier.monthly_price_in_cents / 100,
          "chargeName" => "Not a matching charge name",
        )
        refute @published_tier.matches_invoice_item?(invoice_item)
      end

      test "true with a monthly charge for a different tier price on the same listing" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "unitPrice"  => @published_tier.monthly_price_in_cents / 100 + 20,
          "chargeName" => @published_tier.listing.monthly_plan_or_charge_name,
        )
        assert @published_tier.matches_invoice_item?(invoice_item)
      end

      test "true with a yearly charge for a different tier price on the same listing" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "unitPrice"  => @published_tier.yearly_price_in_cents / 100 + 20,
          "chargeName" => @published_tier.listing.yearly_plan_or_charge_name,
        )
        assert @published_tier.matches_invoice_item?(invoice_item)
      end
    end
  end
end if GitHub.billing_enabled?
