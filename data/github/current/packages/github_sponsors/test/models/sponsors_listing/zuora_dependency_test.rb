# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::ZuoraDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @listing = create(:sponsors_listing, :approved)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#zuora_rate_plan_charge_ids" do
    test "returns nil for invalid billing cycle" do
      assert_nil @listing.zuora_rate_plan_charge_ids(billing_cycle: "foo")
    end

    test "returns nil for missing product UUID, logs message, and enqueues sync job" do
      billing_cycle = User::BillingDependency::MONTHLY_PLAN
      product_key = @listing.product_key(billing_cycle: billing_cycle)
      refute Billing::ProductUUID.sponsors_listings.with_product_key(product_key).exists?,
        "need matching ProductUUID to not exist for the listing"

      assert_logged(
        Body: "Sponsors listing is missing necessary Zuora product",
        "gh.user.id": @listing.sponsorable_id,
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": "SponsorsListing",
        "code.function": "zuora_rate_plan_charge_ids",
        "gh.billing_cycle": billing_cycle,
      ) do
        assert_enqueued_with(job: SponsorsListingZuoraSyncJob, args: [@listing]) do
          assert_nil @listing.zuora_rate_plan_charge_ids(billing_cycle: billing_cycle)
        end
      end
    end

    test "returns nil for missing product UUID but does not log message or enqueue sync job for unapproved listing" do
      draft_listing = create(:sponsors_listing)
      refute_predicate draft_listing, :approved?

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_nil draft_listing.zuora_rate_plan_charge_ids(billing_cycle: User::BillingDependency::MONTHLY_PLAN)
        end
      end
    end

    test "returns monthly rate plan charge IDs" do
      zuora_product_rate_plan_charge_ids = { flat: "abc123", fee: "987zyx" }
      create(:billing_product_uuid, :sponsors_listing, :monthly, listing: @listing,
        zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charge_ids)

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: User::BillingDependency::MONTHLY_PLAN)
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: "monTH")
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: :Month)
        end
      end
    end

    test "returns annual rate plan charge IDs" do
      zuora_product_rate_plan_charge_ids = { flat: "abc123", fee: "987zyx" }
      create(:billing_product_uuid, :sponsors_listing, :yearly, listing: @listing,
        zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charge_ids)

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: User::BillingDependency::YEARLY_PLAN)
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: "yeaR")
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: :YEAR)
        end
      end
    end

    test "returns one-time rate plan charge IDs" do
      zuora_product_rate_plan_charge_ids = { flat: "abc123", fee: "987zyx" }
      create(:billing_product_uuid, :sponsors_listing, :one_time, listing: @listing,
        zuora_product_rate_plan_charge_ids: zuora_product_rate_plan_charge_ids)

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: Billing::ProductUUID::ONE_TIME_BILLING_CYCLE)
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: "ONE_time")
          assert_equal zuora_product_rate_plan_charge_ids,
            @listing.zuora_rate_plan_charge_ids(billing_cycle: :one_time)
        end
      end
    end
  end

  context "#zuora_rate_plan_id" do
    test "returns nil for invalid billing cycle" do
      assert_nil @listing.zuora_rate_plan_id(billing_cycle: "foo")
    end

    test "returns nil for missing product UUID, logs message, and enqueues sync job" do
      billing_cycle = User::BillingDependency::MONTHLY_PLAN
      product_key = @listing.product_key(billing_cycle: billing_cycle)
      refute Billing::ProductUUID.sponsors_listings.with_product_key(product_key).exists?,
        "need matching ProductUUID to not exist for the listing"

      assert_logged(
        Body: "Sponsors listing is missing necessary Zuora product",
        "gh.user.id": @listing.sponsorable_id,
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": "SponsorsListing",
        "code.function": "zuora_rate_plan_id",
        "gh.billing_cycle": billing_cycle,
      ) do
        assert_enqueued_with(job: SponsorsListingZuoraSyncJob, args: [@listing]) do
          assert_nil @listing.zuora_rate_plan_id(billing_cycle: billing_cycle)
        end
      end
    end

    test "returns nil for missing product UUID but does not log message or enqueue sync job for unapproved listing" do
      draft_listing = create(:sponsors_listing)
      refute_predicate draft_listing, :approved?

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_nil draft_listing.zuora_rate_plan_id(billing_cycle: User::BillingDependency::MONTHLY_PLAN)
        end
      end
    end

    test "returns monthly rate plan ID" do
      create(:billing_product_uuid, :sponsors_listing, :monthly, listing: @listing, zuora_product_rate_plan_id: "foo")

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: User::BillingDependency::MONTHLY_PLAN)
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: "Month")
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: :month)
        end
      end
    end

    test "returns annual rate plan ID" do
      create(:billing_product_uuid, :sponsors_listing, :yearly, listing: @listing, zuora_product_rate_plan_id: "foo")

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: User::BillingDependency::YEARLY_PLAN)
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: "YeAr")
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: :year)
        end
      end
    end

    test "returns one-time rate plan ID" do
      create(:billing_product_uuid, :sponsors_listing, :one_time, listing: @listing,
        zuora_product_rate_plan_id: "foo")

      refute_logged(Body: "Sponsors listing is missing necessary Zuora product") do
        assert_no_enqueued_jobs(only: SponsorsListingZuoraSyncJob) do
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: Billing::ProductUUID::ONE_TIME_BILLING_CYCLE)
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: "One_Time")
          assert_equal "foo", @listing.zuora_rate_plan_id(billing_cycle: :One_time)
        end
      end
    end
  end

  context ".fee_charge_name_for" do
    test "appends suffix to given string to imply it's a service fee charge" do
      assert_equal "foo fee", SponsorsListing.fee_charge_name_for("foo")
    end
  end

  context "#product_uuid" do
    test "returns the monthly product UUID for the listing when one exists" do
      assert_nil @listing.product_uuid("month")

      product_uuid = create(:billing_product_uuid, :sponsors_listing, listing: @listing)
      assert_equal product_uuid, @listing.reload.product_uuid("month")
    end

    test "returns the yearly product UUID for the listing when one exists" do
      assert_nil @listing.product_uuid("year")

      product_uuid = create(:billing_product_uuid, :yearly, :sponsors_listing, listing: @listing)
      assert_equal product_uuid, @listing.reload.product_uuid("year")
    end

    test "returns the one-time product UUID for the listing when one exists" do
      assert_nil @listing.product_uuid("one_time")

      product_uuid = create(:billing_product_uuid, :one_time, :sponsors_listing, listing: @listing)
      assert_equal product_uuid, @listing.reload.product_uuid("one_time")
    end

    test "can be batch loaded for multiple listings" do
      listing1 = @listing
      listing2, listing3 = create_pair(:sponsors_listing, :approved)
      listings = [listing1, listing2, listing3]
      listing1_product_uuid = create(:billing_product_uuid, :sponsors_listing, listing: listing1)
      listing3_product_uuid = create(:billing_product_uuid, :sponsors_listing, listing: listing3)

      assert_query_count_per_table({ product_uuids: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(listings, :product_uuid, "month")
      end
      assert_query_count_per_table({ product_uuids: 0 }) do
        assert_equal listing1_product_uuid, listing1.product_uuid("month")
        assert_nil listing2.product_uuid("month")
        assert_equal listing3_product_uuid, listing3.product_uuid("month")
      end
    end
  end

  context "#update_zuora_product_and_maintainer_name" do
    test "no-op when the Zuora product does not exist" do
      old_slug = @listing.slug
      new_login = "someNewUsername"
      new_slug = SponsorsListing.slug_for(new_login)

      with_live_zuora("zuora/sponsors_no_product_to_rename") do
        product_id = @listing.zuora_product_id
        assert_nil product_id, "need a listing with a nil Zuora product ID"

        GitHub.dogstats.expects(:increment).once
          .with("sponsors_listing.zuora_product_rename", tags: ["old_product_exists:false"])

        zuora_success = @listing.update_zuora_product_and_maintainer_name(
          old_slug: old_slug,
          new_slug: new_slug,
          new_login: new_login,
        )

        assert zuora_success
      end
    end

    test "updates the product name and maintainer name for the product identified by the given old Sponsors listing slug" do
      old_slug = @listing.slug
      new_login = "someNewUsername"
      new_slug = SponsorsListing.slug_for(new_login)

      with_live_zuora("zuora/sponsors_product_rename") do
        @listing.send(:create_zuora_product)
        product_id = @listing.zuora_product_id
        assert_predicate product_id, :present?, "should have a Zuora product ID now that the product has been created"

        GitHub.dogstats.expects(:increment).once
          .with("sponsors_listing.zuora_product_rename", tags: ["old_product_exists:true", "success:true"])

        zuora_success = @listing.update_zuora_product_and_maintainer_name(
          old_slug: old_slug,
          new_slug: new_slug,
          new_login: new_login,
        )

        assert zuora_success, "should have returned true to indicate the update happened"
        result = GitHub.zuorest_client.query_action queryString: <<-ZOQL
          SELECT Name, MaintainerName__c FROM Product
          WHERE Id = '#{product_id}'
        ZOQL
        assert_equal 1, result["size"], "should still be a Zuora product with the same ID"
        first_record = result["records"].first
        assert_equal new_slug, first_record["Name"], "should have renamed the Zuora product"
        assert_equal new_login, first_record["MaintainerName__c"],
          "should have updated the Zuora product's maintainer name"
      end
    end
  end

  context "#sync_to_zuora" do
    test "does not create product in zuora if listing is not approved" do
      pending_listing = create(:sponsors_listing, :pending_approval)

      GitHub.zuorest_client.expects(:create_product).never

      pending_listing.sync_to_zuora
    end

    test "creates product in zuora if one doesn't exist" do
      with_live_zuora("zuora/sponsors_listing_product") do
        assert_difference "Billing::ProductUUID.count", 3 do
          @listing.sync_to_zuora
        end

        Billing::ProductUUID.billing_cycles.keys.each do |cycle|
          product_key = @listing.product_key(billing_cycle: cycle)

          uuid = Billing::ProductUUID.find_by!(product_type: SponsorsListing::ZuoraDependency::ZUORA_PRODUCT_TYPE, product_key: product_key)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:flat]
          assert uuid.zuora_product_rate_plan_charge_ids[:fee]

          assert_equal cycle, uuid.billing_cycle
        end
      end
    end

    test "limits database lookups for product UUIDs" do
      with_live_zuora("zuora/sponsors_listing_product") do
        assert_query_count_per_table({ product_uuids: 7 }) do # 4 reads, 3 writes
          @listing.sync_to_zuora
        end
      end
    end

    test "uses existing product in zuora if one does exist" do
      with_live_zuora("zuora/sponsors_listing_product") do
        existing_product_id = @listing.send(:create_zuora_product)

        GitHub.zuorest_client.expects(:create_product).never

        assert_difference "Billing::ProductUUID.count", 3 do
          @listing.sync_to_zuora
        end

        Billing::ProductUUID.billing_cycles.keys.each do |cycle|
          product_key = @listing.product_key(billing_cycle: cycle)

          uuid = Billing::ProductUUID.find_by!(product_type: SponsorsListing::ZuoraDependency::ZUORA_PRODUCT_TYPE, product_key: product_key)
          assert_equal existing_product_id, uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:flat]
          assert uuid.zuora_product_rate_plan_charge_ids[:fee]

          assert_equal cycle, uuid.billing_cycle
        end
      end
    end

    test "rerunnable if rate plans are present in Zuora" do
      with_live_zuora("zuora/sponsors_listing_product_rerunnability") do
        # need a stable identifier to match those used in Zuora
        maintainer = create(:user, id: 100_000, login: "sponsors-listing-zuora-sync-dup")
        listing = create(:sponsors_listing, :approved, sponsorable: maintainer)

        assert_difference "Billing::ProductUUID.count", 3 do
          listing.sync_to_zuora
        end

        Billing::ProductUUID.billing_cycles.keys.each do |cycle|
          product_key = listing.product_key(billing_cycle: cycle)

          uuid = Billing::ProductUUID.find_by!(product_type: SponsorsListing::ZuoraDependency::ZUORA_PRODUCT_TYPE, product_key: product_key)
          assert_equal listing.zuora_product_id, uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:flat]
          assert uuid.zuora_product_rate_plan_charge_ids[:fee]

          assert_equal cycle, uuid.billing_cycle
        end
      end
    end

    test "sponsors listing product for sponsored developer gets the correct custom attributes" do
      mock_zuora = FakeZuora.mock
      Timecop.freeze do
        @listing.sync_to_zuora

        backdated_start_date = (GitHub::Billing.today - 1.year).to_s
        product = mock_zuora.calls[FakeZuora::CREATE_PRODUCT_PATH].first
        assert_equal @listing.sponsorable_login, product[:MaintainerName__c]
        assert_equal @listing.zuora_slug, product[:MaintainerSlug__c]
        assert_equal "sponsorships", product[:ProductCategory__c]
        assert_equal backdated_start_date, product[:EffectiveStartDate]
      end
    end

    test "sponsors listing product for sponsored organization gets the correct custom attributes" do
      mock_zuora = FakeZuora.mock

      org = create(:organization, :sponsorable)
      org_listing = org.sponsors_listing
      org_listing.sync_to_zuora

      product = mock_zuora.calls[FakeZuora::CREATE_PRODUCT_PATH].first
      assert_equal org.login, product[:MaintainerName__c]
      assert_equal org_listing.zuora_slug, product[:MaintainerSlug__c]
      assert_equal "sponsorships", product[:ProductCategory__c]
    end
  end
end if GitHub.billing_enabled?
