# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::SponsorshipsExportTest < GitHub::TestCase
  include ActionView::Helpers::NumberHelper

  fixtures do
    travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1)

    @user = create(:user, :sponsorable)
    @listing = @user.sponsors_listing
    @stripe_account = create(:stripe_connect_account, sponsors_listing: @listing)
    @tier = @listing.default_tier

    @sponsor = create(:credit_card_user,
      login: "sponsor#{SponsorsListing::SponsorshipsExport::START_YEAR}",
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @org_admin = create(:user)
    @org = create(:organization, :sponsorable, admin: @org_admin)
    @org_listing = @org.sponsors_listing
    @org_tier = @org_listing.default_tier

    @sponsor_for_org = create(:credit_card_user,
      login: "sponsorForOrg#{SponsorsListing::SponsorshipsExport::START_YEAR}",
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 2)
    @patreon_sponsorship = create(:sponsorship, payment_source: "patreon",
      sponsorable: @user,
      tier: @tier,
      sponsor: create(:user, login: "patreon-sponsor")
    )
    travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 3)
    @sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item,
      sponsorable: @user,
      tier: @tier,
      sponsor: @sponsor,
    )
    @new_user_sponsorship_activity = create(:sponsors_activity, :new_sponsorship,
      sponsorable: @user,
      sponsor: @sponsor,
      sponsorable_metadata: { "source" => "hacktoberfest", "year" => 2021 })
    @upgrade_user_sponsorship_activity = create(:sponsors_activity, :upgrade,
      sponsorable: @user,
      sponsor: @sponsor,
      sponsorable_metadata: { "source" => "back-to-school" })
    travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 4)
    @org_sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item,
      sponsorable: @org,
      tier: @org_tier,
      sponsor: @sponsor_for_org,
    )

    # Return to present day
    travel_back

    travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 5)

    @private_sponsor = create(:credit_card_user,
      login: "privateSponsor#{SponsorsListing::SponsorshipsExport::START_YEAR}",
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @private_sponsor_for_org = create(:credit_card_user,
      login: "privateSponsorForOrg#{SponsorsListing::SponsorshipsExport::START_YEAR}",
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    @private_sponsorship = create(:sponsorship, :private, :with_billing_transaction_and_line_item,
      sponsorable: @user,
      tier: @tier,
      sponsor: @private_sponsor,
    )
    @org_private_sponsorship = create(:sponsorship, :private,
      :with_billing_transaction_and_line_item,
      sponsorable: @org,
      tier: @org_tier,
      sponsor: @private_sponsor_for_org,
    )

    @new_org_sponsorship_activity = create(:sponsors_activity, :new_sponsorship,
      sponsorable: @org,
      sponsor: @private_sponsor_for_org,
      sponsorable_metadata: { "source" => "hacktoberfest", "year" => 2021 })
    @upgrade_org_sponsorship_activity = create(:sponsors_activity, :upgrade,
      sponsorable: @org,
      sponsor: @private_sponsor_for_org,
      sponsorable_metadata: { "source" => "back-to-school" })

    travel_back
  end

  setup do
    skip unless GitHub.sponsors_enabled?

    @line_item = Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .where(billing_transactions: { user_id: @sponsor })
      .where(subscribable: @tier)
      .first
    @private_line_item = Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .where(billing_transactions: { user_id: @private_sponsor })
      .where(subscribable: @tier)
      .first

    @org_line_item = Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .where(billing_transactions: { user_id: @sponsor_for_org })
      .where(subscribable: @org_tier)
      .first
    @org_private_line_item = Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .where(billing_transactions: { user_id: @private_sponsor_for_org })
      .where(subscribable: @org_tier)
      .first

    @expected_json_metadata = { source: %w[back-to-school hacktoberfest], year: [2021] }
  end

  def hacky_destroy_sponsorship(sponsor:, sponsorable:)
    # HACK HACK HACK we want the line items the factory provides, but in our system sponsorships are mutable,
    # so this approximates that by destroying the existing sponsorship first
    T.must(Sponsorship
      .from_sponsor(sponsor)
      .with_user_or_org_sponsorable(sponsorable)
      .first)
      .destroy
  end

  context "JSON format" do
    test "returns JSON for user" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@line_item.amount_in_cents / 100),
            is_prorated: @line_item.billing_transaction.prorated_charge?,
            status: @line_item.billing_transaction.last_status,
            transaction_date: @line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @private_line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@private_line_item.amount_in_cents / 100),
            is_prorated: @private_line_item.billing_transaction.prorated_charge?,
            status: @private_line_item.billing_transaction.last_status,
            transaction_date: @private_line_item.created_at,
            billing_country: @private_line_item.billing_country,
            billing_region: @private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
      assert_equal "#{Date::MONTHNAMES[1]} #{SponsorsListing::SponsorshipsExport::START_YEAR}",
        export.description
    end

    test "returns JSON for sponsorable with enterprise account member org sponsorship" do
      travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1)

      member_org_sub_item = create(:sponsors_subscription_item, :self_serve_business)
      member_org = member_org_sub_item.organization
      tier = member_org_sub_item.subscribable
      member_org_sponsorship = create(:sponsorship,
        sponsor: member_org,
        tier: tier,
        subscription_item: member_org_sub_item
      )
      member_org_transaction = create(:billing_transaction, :business_owned, customer: member_org_sub_item.customer)
      member_org_line_item = create(:billing_transaction_line_item,
        billing_transaction: member_org_transaction,
        subscribable: tier,
        amount_in_cents: tier.monthly_price_in_cents,
        extras: { managing_entity_id: member_org_sub_item.organization_id }
      )

      travel_back

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: tier.listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_member_org_sponsorship = T.let({
        sponsor_handle: member_org.login,
        sponsor_profile_name: member_org.profile_name,
        sponsor_public_email: member_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: member_org_sponsorship.created_at,
        is_public: true,
        is_yearly: true,
        transactions: [
          {
            transaction_id: member_org_line_item.billing_transaction.transaction_id,
            tier_name: tier.name,
            tier_monthly_amount: number_to_currency(tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(member_org_line_item.amount_in_cents / 100),
            is_prorated: member_org_line_item.billing_transaction.prorated_charge?,
            status: member_org_line_item.billing_transaction.last_status,
            transaction_date: member_org_line_item.created_at,
            billing_country: member_org_line_item.billing_country,
            billing_region: member_org_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected = [expected_member_org_sponsorship].to_json
      assert_equal expected, export.fetch_content
    end

    test "loads data for each sponsor in a reasonable number of queries" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      assert_query_count(13, ignore_feature_flags: true) do
        export.fetch_content
      end
    end

    test "returns JSON for user with sponsorable metadata" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@line_item.amount_in_cents / 100),
            is_prorated: @line_item.billing_transaction.prorated_charge?,
            status: @line_item.billing_transaction.last_status,
            transaction_date: @line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @private_line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@private_line_item.amount_in_cents / 100),
            is_prorated: @private_line_item.billing_transaction.prorated_charge?,
            status: @private_line_item.billing_transaction.last_status,
            transaction_date: @private_line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
      assert_equal "#{Date::MONTHNAMES[1]} #{SponsorsListing::SponsorshipsExport::START_YEAR}",
        export.description
    end

    test "returns JSON for org with sponsorable metadata" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor_for_org.login,
        sponsor_profile_name: @sponsor_for_org.profile_name,
        sponsor_public_email: @sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_line_item.amount_in_cents / 100),
            is_prorated: @org_line_item.billing_transaction.prorated_charge?,
            status: @org_line_item.billing_transaction.last_status,
            transaction_date: @org_line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor_for_org.login,
        sponsor_profile_name: @private_sponsor_for_org.profile_name,
        sponsor_public_email: @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_private_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_private_line_item.amount_in_cents / 100),
            is_prorated: @org_private_line_item.billing_transaction.prorated_charge?,
            status: @org_private_line_item.billing_transaction.last_status,
            transaction_date: @org_private_line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor_for_org.login, @sponsor_for_org.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship].to_json
      assert_equal expected, json
    end

    test "returns JSON for user with sponsorable metadata and tax info" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@line_item.amount_in_cents / 100),
            is_prorated: @line_item.billing_transaction.prorated_charge?,
            status: @line_item.billing_transaction.last_status,
            transaction_date: @line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @private_line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@private_line_item.amount_in_cents / 100),
            is_prorated: @private_line_item.billing_transaction.prorated_charge?,
            status: @private_line_item.billing_transaction.last_status,
            transaction_date: @private_line_item.created_at,
            billing_country: @private_line_item.billing_country,
            billing_region: @private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
      assert_equal "#{Date::MONTHNAMES[1]} #{SponsorsListing::SponsorshipsExport::START_YEAR}",
        export.description
    end

    test "returns JSON for org with sponsorable metadata and tax info" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor_for_org.login,
        sponsor_profile_name: @sponsor_for_org.profile_name,
        sponsor_public_email: @sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_line_item.amount_in_cents / 100),
            is_prorated: @org_line_item.billing_transaction.prorated_charge?,
            status: @org_line_item.billing_transaction.last_status,
            transaction_date: @org_line_item.created_at,
            billing_country: @org_line_item.billing_country,
            billing_region: @org_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor_for_org.login,
        sponsor_profile_name: @private_sponsor_for_org.profile_name,
        sponsor_public_email: @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_private_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_private_line_item.amount_in_cents / 100),
            is_prorated: @org_private_line_item.billing_transaction.prorated_charge?,
            status: @org_private_line_item.billing_transaction.last_status,
            transaction_date: @org_private_line_item.created_at,
            billing_country: @org_private_line_item.billing_country,
            billing_region: @org_private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor_for_org.login, @sponsor_for_org.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship].to_json
      assert_equal expected, json
    end

    test "returns JSON for listing with org business tax identifier" do
      listing = create(:sponsors_listing, :approved)
      sponsorable = listing.sponsorable

      org_business_sponsor = create(:credit_card_organization,
        login: "org-business-#{SponsorsListing::SponsorshipsExport::START_YEAR}",
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )

      org_sponsorship_without_business_tax_identifier = travel_to 1.week.ago do
        create(:sponsorship, :inactive, :one_time, :with_billing_transaction_and_line_item,
          sponsorable: sponsorable,
          sponsor: org_business_sponsor,
        )
      end

      hacky_destroy_sponsorship(sponsor: org_business_sponsor, sponsorable: sponsorable)

      org_sponsorship_with_business_tax_identifier = create(
        :sponsorship, :with_billing_transaction_and_line_item, :with_business_tax_identifier,
        sponsorable: sponsorable,
        sponsor: org_business_sponsor,
      )

      line_items = Billing::BillingTransaction::LineItem
        .sponsorships
        .includes(:billing_transaction)
        .preload(:subscribable)
        .for_subscribable_and_user(listing.sponsors_tiers.map(&:id), org_business_sponsor)
        .newest_first
        .to_a.reject(&:sponsors_fee?)
      assert_equal 2, line_items.size
      newest_line_item, oldest_line_item = T.must(line_items.first), T.must(line_items.last)
      newest_billing_transaction = T.must(newest_line_item.billing_transaction)
      oldest_billing_transaction = T.must(oldest_line_item.billing_transaction)

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: listing,
        timeframe: "all",
        format: :json,
      )

      newest_business_tax_identifier = org_business_sponsor.newest_sponsors_business_tax_identifier

      expected_org_business_sponsorship = T.let({
        sponsor_handle: org_business_sponsor.login,
        sponsor_profile_name: org_business_sponsor.profile_name,
        sponsor_public_email: org_business_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: org_sponsorship_with_business_tax_identifier.activated_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: newest_billing_transaction.transaction_id,
            tier_name: org_sponsorship_with_business_tax_identifier.tier.name,
            tier_monthly_amount: number_to_currency(org_sponsorship_with_business_tax_identifier.tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(newest_line_item.amount_in_cents / 100),
            is_prorated: newest_billing_transaction.prorated_charge?,
            status: newest_billing_transaction.last_status,
            transaction_date: newest_line_item.created_at,
            billing_country: newest_business_tax_identifier.human_country,
            billing_region: newest_business_tax_identifier.human_region,
            vat: newest_business_tax_identifier.vat_code,
          },
          {
            transaction_id: oldest_billing_transaction.transaction_id,
            tier_name: org_sponsorship_without_business_tax_identifier.tier.name,
            tier_monthly_amount: number_to_currency(org_sponsorship_without_business_tax_identifier.tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(oldest_line_item.amount_in_cents / 100),
            is_prorated: oldest_billing_transaction.prorated_charge?,
            status: oldest_billing_transaction.last_status,
            transaction_date: oldest_line_item.created_at,
            billing_country: oldest_line_item.billing_country,
            billing_region: oldest_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_equal [org_business_sponsor.login], JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_org_business_sponsorship].to_json
      assert_equal expected, json
      assert_equal "all time", export.description
    end

    test "returns JSON for org" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor_for_org.login,
        sponsor_profile_name: @sponsor_for_org.profile_name,
        sponsor_public_email: @sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_line_item.amount_in_cents / 100),
            is_prorated: @org_line_item.billing_transaction.prorated_charge?,
            status: @org_line_item.billing_transaction.last_status,
            transaction_date: @org_line_item.created_at,
            billing_country: @org_line_item.billing_country,
            billing_region: @org_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor_for_org.login,
        sponsor_profile_name: @private_sponsor_for_org.profile_name,
        sponsor_public_email: @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @org_private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @org_private_line_item.billing_transaction.transaction_id,
            tier_name: @org_tier.name,
            tier_monthly_amount: number_to_currency(@org_tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@org_private_line_item.amount_in_cents / 100),
            is_prorated: @org_private_line_item.billing_transaction.prorated_charge?,
            status: @org_private_line_item.billing_transaction.last_status,
            transaction_date: @org_private_line_item.created_at,
            billing_country: @org_private_line_item.billing_country,
            billing_region: @org_private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor_for_org.login, @sponsor_for_org.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship].to_json
      assert_equal expected, json
    end

    test "can get line items from all time" do
      sponsorship2019 = travel_to("2019-05-15") do
        create(:sponsorship, :with_billing_transaction_and_line_item,
          sponsorable: @user,
          tier: @tier,
          sponsor_login: "sponsor2019"
        )
      end
      line_item2019 = Billing::BillingTransaction::LineItem
        .joins(:billing_transaction)
        .where(billing_transactions: { user_id: sponsorship2019.sponsor })
        .where(subscribable: @tier)
        .first

      sponsorship2020 = travel_to("2020-10-02") do
        create(:sponsorship, :with_billing_transaction_and_line_item,
          sponsorable: @user,
          tier: @tier,
          sponsor_login: "sponsor2020"
        )
      end
      line_item2020 = Billing::BillingTransaction::LineItem
        .joins(:billing_transaction)
        .where(billing_transactions: { user_id: sponsorship2020.sponsor })
        .where(subscribable: @tier)
        .first

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        format: :json,
        timeframe: "all",
      )

      json = export.fetch_content

      refute_nil json
      results = JSON.parse(T.must(json))
      assert_same_elements [
        sponsorship2020.sponsor.login,
        sponsorship2019.sponsor.login,
        @private_sponsor.login,
        @sponsor.login,
        @patreon_sponsorship.sponsor.login,
      ], results.map { |hash| hash["sponsor_handle"] }
      assert_equal [T.must(T.must(line_item2020).billing_transaction).transaction_id],
        results[0]["transactions"].map { |hash| hash["transaction_id"] },
        "should include sponsorship line item from 2020"
      assert_equal [T.must(T.must(line_item2019).billing_transaction).transaction_id],
        results[1]["transactions"].map { |hash| hash["transaction_id"] },
        "should include sponsorship line item from 2019"
      assert_equal [@private_line_item.billing_transaction.transaction_id],
        results[2]["transactions"].map { |hash| hash["transaction_id"] },
        "should include private sponsorship line item from 2018"
      assert_equal [@line_item.billing_transaction.transaction_id],
        results[3]["transactions"].map { |hash| hash["transaction_id"] },
        "should include public sponsorship line item from 2018"

      assert_equal "#{@user}-sponsorships-all-time.json", export.filename
      assert_equal "all time", export.description
    end

    test "can get line items from a particular year" do
      sponsorship2020 = travel_to("2020-12-03") do
        create(:sponsorship, :with_billing_transaction_and_line_item,
          sponsorable: @user, tier: @tier, sponsor_login: "sponsor2020")
      end
      line_item = Billing::BillingTransaction::LineItem
        .joins(:billing_transaction)
        .where(billing_transactions: { user_id: sponsorship2020.sponsor })
        .where(subscribable: @tier)
        .first

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: 2020,
        timeframe: "year",
        format: :json,
      )

      json = export.fetch_content

      refute_nil json
      results = JSON.parse(T.must(json))
      assert_same_elements [
        sponsorship2020.sponsor.login,
        @private_sponsor.login,
        @sponsor.login,
        @patreon_sponsorship.sponsor.login,
      ], results.map { |hash| hash["sponsor_handle"] },
        "should have all ongoing sponsors regardless of year"
      assert_equal [T.must(T.must(line_item).billing_transaction).transaction_id],
        results[0]["transactions"].map { |hash| hash["transaction_id"] },
        "should include line item from requested year"
      assert_empty results[1]["transactions"],
        "private sponsorship with 2018 line items should have no transactions included"
      assert_empty results[2]["transactions"],
        "public sponsorship with 2018 line items should have no transactions included"
      assert_equal "#{@user}-sponsorships-2020.json", export.filename
      assert_equal "2020", export.description
    end

    test "can filter by year and month" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: 2019,
        month: Date::MONTHNAMES[2],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
    end

    test "can filter sponsorable metadata by year and month" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: 2019,
        month: Date::MONTHNAMES[2],
        format: :json,
      )

      @new_user_sponsorship_activity.update!(created_at: "2019-01-01 15:30:45")
      @upgrade_user_sponsorship_activity.update!(created_at: Time.zone.now)

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
    end

    test "returns the JSON file name" do
      year = SponsorsListing::SponsorshipsExport::START_YEAR
      month = Date::MONTHNAMES[1]

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: year,
        month: month,
        format: :json,
      )

      expected = "#{@org.login}-sponsorships-#{month}-#{year}.json"

      assert_equal expected, export.filename
    end

    test "returns the JSON mime type" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      assert_equal "application/json", export.mime_type
    end

    # https://github.com/github/sponsors/issues/2013
    test "does not round away cents in processed amount" do
      @private_line_item.update!(amount_in_cents: 123)
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json)

      result = export.fetch_content

      refute_nil result
      json = JSON.parse(T.must(result))
      sponsorship_row = json.first
      refute_nil sponsorship_row
      transaction_row = sponsorship_row["transactions"].first
      refute_nil transaction_row
      assert_equal "$1.23", transaction_row["processed_amount"]
    end

    # https://github.com/github/sponsors/issues/3289
    test "handles nil metadata in activity" do
      @new_user_sponsorship_activity.update!(sponsorable_metadata: nil)
      @upgrade_user_sponsorship_activity.update!(sponsorable_metadata: nil)
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json)

      result = export.fetch_content

      refute_nil result
      json = JSON.parse(T.must(result))
      assert_equal 3, json.count
      assert_equal [{}, {}, {}], json.map { |sponsorship| sponsorship["metadata"] }
    end

    test "returns sponsorships ordered by newest" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@line_item.amount_in_cents / 100),
            is_prorated: @line_item.billing_transaction.prorated_charge?,
            status: @line_item.billing_transaction.last_status,
            transaction_date: @line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @private_line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@private_line_item.amount_in_cents / 100),
            is_prorated: @private_line_item.billing_transaction.prorated_charge?,
            status: @private_line_item.billing_transaction.last_status,
            transaction_date: @private_line_item.created_at,
            billing_country: @private_line_item.billing_country,
            billing_region: @private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [@private_sponsor.login, @sponsor.login, @patreon_sponsorship.sponsor.login],
        JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [expected_private_sponsorship, expected_public_sponsorship, expected_patreon_sponsorship].to_json
      assert_equal expected, json
      assert_equal "#{Date::MONTHNAMES[1]} #{SponsorsListing::SponsorshipsExport::START_YEAR}",
        export.description
    end

    # https://github.com/github/github/pull/248894
    test "returns JSON for user that received legacy invoiced sponsorship transfers" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      legacy_transfer = travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 6) do
        create(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing
        )
      end
      legacy_transfer_sponsor = legacy_transfer.sponsor
      # There was a transition from legacy invoiced transfers to transactions that use line items,
      # so we want to also take into account sponsors that fall into that bucket.
      # The factory will try and mess with the sponsorship on create though, so we use a hacky build/save.
      legacy_transfer_future_regular_sponsorships = travel_to(
        Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1),
      ) do
        build(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing,
          stripe_connect_account: @stripe_account,
          sponsor: @sponsor,
        ).tap { |transfer| transfer.save }
      end

      expected_public_sponsorship = T.let({
        sponsor_handle: @sponsor.login,
        sponsor_profile_name: @sponsor.profile_name,
        sponsor_public_email: @sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@line_item.amount_in_cents / 100),
            is_prorated: @line_item.billing_transaction.prorated_charge?,
            status: @line_item.billing_transaction.last_status,
            transaction_date: @line_item.created_at,
            billing_country: @line_item.billing_country,
            billing_region: @line_item.billing_region,
            vat: nil,
          },
          {
            transaction_id: nil,
            tier_name: nil,
            tier_monthly_amount: nil,
            processed_amount: number_to_currency(legacy_transfer_future_regular_sponsorships.amount_in_cents / 100),
            is_prorated: nil,
            status: nil,
            transaction_date: legacy_transfer_future_regular_sponsorships.transfer_created_at,
            billing_country: nil,
            billing_region: nil,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: @expected_json_metadata,
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_private_sponsorship = T.let({
        sponsor_handle: @private_sponsor.login,
        sponsor_profile_name: @private_sponsor.profile_name,
        sponsor_public_email: @private_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: @private_sponsorship.created_at,
        is_public: false,
        is_yearly: false,
        transactions: [
          {
            transaction_id: @private_line_item.billing_transaction.transaction_id,
            tier_name: @tier.name,
            tier_monthly_amount: number_to_currency(@tier.monthly_price_in_dollars),
            processed_amount: number_to_currency(@private_line_item.amount_in_cents / 100),
            is_prorated: @private_line_item.billing_transaction.prorated_charge?,
            status: @private_line_item.billing_transaction.last_status,
            transaction_date: @private_line_item.created_at,
            billing_country: @private_line_item.billing_country,
            billing_region: @private_line_item.billing_region,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_legacy_transfer_sponsorship = T.let({
        sponsor_handle: legacy_transfer_sponsor.login,
        sponsor_profile_name: legacy_transfer_sponsor.profile_name,
        sponsor_public_email: legacy_transfer_sponsor.publicly_visible_email(logged_in: true),
        sponsorship_started_on: legacy_transfer.sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [
          {
            transaction_id: nil,
            tier_name: nil,
            tier_monthly_amount: nil,
            processed_amount: number_to_currency(legacy_transfer.amount_in_cents / 100),
            is_prorated: nil,
            status: nil,
            transaction_date: legacy_transfer.transfer_created_at,
            billing_country: nil,
            billing_region: nil,
            vat: nil,
          },
        ],
        payment_source: "github",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      expected_patreon_sponsorship = T.let({
        sponsor_handle: @patreon_sponsorship.sponsor.login,
        sponsor_profile_name: nil,
        sponsor_public_email: nil,
        sponsorship_started_on: @patreon_sponsorship.created_at,
        is_public: true,
        is_yearly: false,
        transactions: [],
        payment_source: "patreon",
        metadata: {},
      }, SponsorsListing::SponsorshipsExport::SponsorshipHashType)

      json = export.fetch_content

      refute_nil json
      assert_same_elements [legacy_transfer_sponsor.login, @private_sponsor.login, @sponsor.login,
        @patreon_sponsorship.sponsor.login], JSON.parse(T.must(json)).map { |hash| hash["sponsor_handle"] }
      expected = [
        expected_legacy_transfer_sponsorship,
        expected_private_sponsorship,
        expected_public_sponsorship,
        expected_patreon_sponsorship
      ].to_json
      assert_equal expected, json
      assert_equal "#{Date::MONTHNAMES[1]} #{SponsorsListing::SponsorshipsExport::START_YEAR}",
        export.description
    end
  end

  context "CSV format" do
    test "returns CSV for user" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for sponsorable with enterprise account member org sponsorship" do
      travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1)

      member_org_sub_item = create(:sponsors_subscription_item, :self_serve_business)
      member_org = member_org_sub_item.organization
      tier = member_org_sub_item.subscribable
      member_org_sponsorship = create(:sponsorship,
        sponsor: member_org,
        tier: tier,
        subscription_item: member_org_sub_item
      )
      member_org_transaction = create(:billing_transaction, :business_owned, customer: member_org_sub_item.customer)
      member_org_line_item = create(:billing_transaction_line_item,
        billing_transaction: member_org_transaction,
        subscribable: tier,
        amount_in_cents: tier.monthly_price_in_cents,
        extras: { managing_entity_id: member_org_sub_item.organization_id }
      )

      travel_back

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: tier.listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_member_org_sponsorship = T.let([
        member_org.login,
        member_org.profile_name,
        member_org.publicly_visible_email(logged_in: true),
        member_org_sponsorship.created_at,
        true,
        true,
        member_org_line_item.billing_transaction.transaction_id,
        member_org_sponsorship.payment_source.to_s,
        tier.name,
        number_to_currency(tier.monthly_price_in_dollars),
        number_to_currency(member_org_line_item.amount_in_cents / 100),
        member_org_line_item.billing_transaction.prorated_charge?,
        member_org_line_item.billing_transaction.last_status,
        member_org_line_item.created_at,
        "\"\"",
        member_org_line_item.billing_country,
        member_org_line_item.billing_region,
        nil
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_member_org_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    # https://github.com/github/sponsors/issues/5221
    test "CSV has the same number of headers and data columns" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType)

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType)

      assert_equal SponsorsListing::SponsorshipsExport::CSV_HEADERS.length, expected_public_sponsorship.length

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship.join(",")}
        #{expected_public_sponsorship.join(",")}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for user with VAT" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        @private_sponsor.sponsor_sales_tax_vat_id,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for user with business tax identifier" do
      listing = create(:sponsors_listing, :approved)
      sponsorable = listing.sponsorable

      org_business_sponsor = create(:credit_card_organization,
        login: "org-business-#{SponsorsListing::SponsorshipsExport::START_YEAR}",
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )

      org_sponsorship_without_business_tax_identifier = travel_to 1.week.ago do
        create(:sponsorship, :inactive, :one_time, :with_billing_transaction_and_line_item,
          sponsorable: sponsorable,
          sponsor: org_business_sponsor,
        )
      end

      hacky_destroy_sponsorship(sponsor: org_business_sponsor, sponsorable: sponsorable)

      org_sponsorship_with_business_tax_identifier = create(
        :sponsorship, :with_billing_transaction_and_line_item, :with_business_tax_identifier,
        sponsorable: sponsorable,
        sponsor: org_business_sponsor,
      )

      line_items = Billing::BillingTransaction::LineItem
        .sponsorships
        .includes(:billing_transaction)
        .preload(:subscribable)
        .for_subscribable_and_user(listing.sponsors_tiers.map(&:id), org_business_sponsor)
        .newest_first
        .to_a.reject(&:sponsors_fee?)
      assert_equal 2, line_items.size
      newest_line_item, oldest_line_item = T.must(line_items.first), T.must(line_items.last)
      newest_billing_transaction = T.must(newest_line_item.billing_transaction)
      oldest_billing_transaction = T.must(oldest_line_item.billing_transaction)

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: listing,
        timeframe: "all",
        format: :csv,
      )

      newest_business_tax_identifier = org_business_sponsor.newest_sponsors_business_tax_identifier

      expected_newest_org_business_sponsorship = T.let([
        org_business_sponsor.login,
        org_business_sponsor.profile_name,
        org_business_sponsor.publicly_visible_email(logged_in: true),
        T.must(org_sponsorship_with_business_tax_identifier.activated_at),
        true,
        false,
        newest_billing_transaction.transaction_id,
        org_sponsorship_with_business_tax_identifier.payment_source.to_s,
        org_sponsorship_with_business_tax_identifier.tier.name,
        number_to_currency(org_sponsorship_with_business_tax_identifier.tier.monthly_price_in_dollars),
        number_to_currency(newest_line_item.amount_in_cents / 100),
        newest_billing_transaction.prorated_charge?,
        newest_billing_transaction.last_status,
        T.must(newest_line_item.created_at),
        "\"\"",
        newest_business_tax_identifier.human_country,
        newest_business_tax_identifier.human_region,
        newest_business_tax_identifier.vat_code,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_previous_org_business_sponsorship = T.let([
        org_business_sponsor.login,
        org_business_sponsor.profile_name,
        org_business_sponsor.publicly_visible_email(logged_in: true),
        T.must(org_sponsorship_with_business_tax_identifier.activated_at), # We've lost history of when this started
        true,
        false,
        oldest_billing_transaction.transaction_id,
        org_sponsorship_without_business_tax_identifier.payment_source.to_s,
        org_sponsorship_without_business_tax_identifier.tier.name,
        number_to_currency(org_sponsorship_without_business_tax_identifier.tier.monthly_price_in_dollars),
        number_to_currency(oldest_line_item.amount_in_cents / 100),
        oldest_billing_transaction.prorated_charge?,
        oldest_billing_transaction.last_status,
        T.must(oldest_line_item.created_at),
        "\"\"",
        oldest_line_item.billing_country,
        oldest_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_newest_org_business_sponsorship}
        #{expected_previous_org_business_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for org with VAT" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor_for_org.login,
        @sponsor_for_org.profile_name,
        @sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_sponsorship.created_at,
        true,
        false,
        @org_line_item.billing_transaction.transaction_id,
        @org_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_line_item.amount_in_cents / 100),
        @org_line_item.billing_transaction.prorated_charge?,
        @org_line_item.billing_transaction.last_status,
        @org_line_item.created_at,
        "\"\"",
        @org_line_item.billing_country,
        @org_line_item.billing_region,
        @sponsor_for_org.sponsor_sales_tax_vat_id,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor_for_org.login,
        @private_sponsor_for_org.profile_name,
        @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_private_sponsorship.created_at,
        false,
        false,
        @org_private_line_item.billing_transaction.transaction_id,
        @org_private_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_private_line_item.amount_in_cents / 100),
        @org_private_line_item.billing_transaction.prorated_charge?,
        @org_private_line_item.billing_transaction.last_status,
        @org_private_line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @org_private_line_item.billing_country,
        @org_private_line_item.billing_region,
        @private_sponsor_for_org.sponsor_sales_tax_vat_id,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for user with sponsorable metadata" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for user with VAT and sponsorable metadata" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        @sponsor.sponsor_sales_tax_vat_id,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        @private_sponsor.sponsor_sales_tax_vat_id,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for org" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor_for_org.login,
        @sponsor_for_org.profile_name,
        @sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_sponsorship.created_at,
        true,
        false,
        @org_line_item.billing_transaction.transaction_id,
        @org_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_line_item.amount_in_cents / 100),
        @org_line_item.billing_transaction.prorated_charge?,
        @org_line_item.billing_transaction.last_status,
        @org_line_item.created_at,
        "\"\"",
        @org_line_item.billing_country,
        @org_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor_for_org.login,
        @private_sponsor_for_org.profile_name,
        @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_private_sponsorship.created_at,
        false,
        false,
        @org_private_line_item.billing_transaction.transaction_id,
        @org_private_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_private_line_item.amount_in_cents / 100),
        @org_private_line_item.billing_transaction.prorated_charge?,
        @org_private_line_item.billing_transaction.last_status,
        @org_private_line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @org_private_line_item.billing_country,
        @org_private_line_item.billing_region,
        nil
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns CSV for org with sponsorable metadata" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor_for_org.login,
        @sponsor_for_org.profile_name,
        @sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_sponsorship.created_at,
        true,
        false,
        @org_line_item.billing_transaction.transaction_id,
        @org_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_line_item.amount_in_cents / 100),
        @org_line_item.billing_transaction.prorated_charge?,
        @org_line_item.billing_transaction.last_status,
        @org_line_item.created_at,
        "\"\"",
        @org_line_item.billing_country,
        @org_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor_for_org.login,
        @private_sponsor_for_org.profile_name,
        @private_sponsor_for_org.publicly_visible_email(logged_in: true),
        @org_private_sponsorship.created_at,
        false,
        false,
        @org_private_line_item.billing_transaction.transaction_id,
        @org_private_sponsorship.payment_source.to_s,
        @org_tier.name,
        number_to_currency(@org_tier.monthly_price_in_dollars),
        number_to_currency(@org_private_line_item.amount_in_cents / 100),
        @org_private_line_item.billing_transaction.prorated_charge?,
        @org_private_line_item.billing_transaction.last_status,
        @org_private_line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @org_private_line_item.billing_country,
        @org_private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "can filter by year and month" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: 2019,
        month: Date::MONTHNAMES[2],
        format: :csv,
      )

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "can filter sponsorable metadata by year and month" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: 2018,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      @new_user_sponsorship_activity.update!(created_at: "2018-02-02 15:30:45")
      @upgrade_user_sponsorship_activity.update!(created_at: Time.zone.now)

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    test "returns the CSV file name" do
      year = SponsorsListing::SponsorshipsExport::START_YEAR
      month = Date::MONTHNAMES[1]

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: year,
        month: month,
        format: :csv,
      )

      expected = "#{@user.login}-sponsorships-#{month}-#{year}.csv"

      assert_equal expected, export.filename
    end

    test "returns the CSV mime type" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      assert_equal "text/csv", export.mime_type
    end

    test "returns sponsorships ordered by newest" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        @line_item.billing_country,
        @line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        @private_line_item.billing_country,
        @private_line_item.billing_region,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
      CSV

      assert_equal expected, export.fetch_content
    end

    # https://github.com/github/github/pull/248894
    test "returns CSV for user that received legacy invoiced sponsorship transfers" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      legacy_transfer = travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 6) do
        create(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing
        )
      end
      legacy_transfer_sponsor = legacy_transfer.sponsor
      # There was a transition from legacy invoiced transfers to transactions that use line items,
      # so we want to also take into account sponsors that fall into that bucket.
      # The factory will try and mess with the sponsorship on create though, so we use a hacky build/save.
      legacy_transfer_future_regular_sponsorships = travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1) do
        build(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing,
          stripe_connect_account: @stripe_account,
          sponsor: @sponsor,
        ).tap { |transfer| transfer.save }
      end

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        "USA",
        "California",
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_prior_legacy_transfer = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        nil,
        @sponsorship.payment_source.to_s,
        nil,
        nil,
        "\"#{number_to_currency(legacy_transfer_future_regular_sponsorships.amount_in_cents / 100)}\"",
        nil,
        nil,
        legacy_transfer_future_regular_sponsorships.transfer_created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        nil,
        nil,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        "USA",
        "California",
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_legacy_transfer = T.let([
        legacy_transfer_sponsor.login,
        legacy_transfer_sponsor.profile_name,
        legacy_transfer_sponsor.publicly_visible_email(logged_in: true),
        legacy_transfer.sponsorship.created_at,
        true,
        false,
        nil,
        legacy_transfer.sponsorship.payment_source.to_s,
        nil,
        nil,
        "\"#{number_to_currency(legacy_transfer.amount_in_cents / 100)}\"",
        nil,
        nil,
        legacy_transfer.transfer_created_at,
        "\"\"",
        nil,
        nil,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_legacy_transfer}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
        #{expected_prior_legacy_transfer}
      CSV

      assert_equal expected, export.fetch_content
    end

    # https://github.com/github/sponsors/issues/5221
    test "CSV has the same number of headers and data columns for legacy transfers" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: :csv,
      )

      legacy_transfer = travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 6) do
        create(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing
        )
      end
      legacy_transfer_sponsor = legacy_transfer.sponsor
      # There was a transition from legacy invoiced transfers to transactions that use line items,
      # so we want to also take into account sponsors that fall into that bucket.
      # The factory will try and mess with the sponsorship on create though, so we use a hacky build/save.
      legacy_transfer_future_regular_sponsorships = travel_to Time.new(SponsorsListing::SponsorshipsExport::START_YEAR, 1, 1) do
        build(:invoiced_sponsorship_transfer, :completed,
          sponsors_listing: @listing,
          stripe_connect_account: @stripe_account,
          sponsor: @sponsor,
        ).tap { |transfer| transfer.save }
      end

      expected_public_sponsorship = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        @line_item.billing_transaction.transaction_id,
        @sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@line_item.amount_in_cents / 100),
        @line_item.billing_transaction.prorated_charge?,
        @line_item.billing_transaction.last_status,
        @line_item.created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        "USA",
        "California",
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_prior_legacy_transfer = T.let([
        @sponsor.login,
        @sponsor.profile_name,
        @sponsor.publicly_visible_email(logged_in: true),
        @sponsorship.created_at,
        true,
        false,
        nil,
        @sponsorship.payment_source.to_s,
        nil,
        nil,
        "\"#{number_to_currency(legacy_transfer_future_regular_sponsorships.amount_in_cents / 100)}\"",
        nil,
        nil,
        legacy_transfer_future_regular_sponsorships.transfer_created_at,
        "\"source: back-to-school, source: hacktoberfest, year: 2021\"",
        nil,
        nil,
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_private_sponsorship = T.let([
        @private_sponsor.login,
        @private_sponsor.profile_name,
        @private_sponsor.publicly_visible_email(logged_in: true),
        @private_sponsorship.created_at,
        false,
        false,
        @private_line_item.billing_transaction.transaction_id,
        @private_sponsorship.payment_source.to_s,
        @tier.name,
        number_to_currency(@tier.monthly_price_in_dollars),
        number_to_currency(@private_line_item.amount_in_cents / 100),
        @private_line_item.billing_transaction.prorated_charge?,
        @private_line_item.billing_transaction.last_status,
        @private_line_item.created_at,
        "\"\"",
        "USA",
        "California",
        nil,
      ], SponsorsListing::SponsorshipsExport::CsvRowType).join(",")

      expected_legacy_transfer_data = [
        legacy_transfer_sponsor.login,
        legacy_transfer_sponsor.profile_name,
        legacy_transfer_sponsor.publicly_visible_email(logged_in: true),
        legacy_transfer.sponsorship.created_at,
        true,
        false,
        nil,
        legacy_transfer.sponsorship.payment_source.to_s,
        nil,
        nil,
        "\"#{number_to_currency(legacy_transfer.amount_in_cents / 100)}\"",
        nil,
        nil,
        legacy_transfer.transfer_created_at,
        "\"\"",
        nil,
        nil,
        nil,
      ]

      assert_equal SponsorsListing::SponsorshipsExport::CSV_HEADERS.length, expected_legacy_transfer_data.length

      expected = <<~CSV
        #{SponsorsListing::SponsorshipsExport::CSV_HEADERS.join(",")}
        #{expected_legacy_transfer_data.join(",")}
        #{expected_private_sponsorship}
        #{expected_public_sponsorship}
        #{expected_prior_legacy_transfer}
      CSV

      assert_equal expected, export.fetch_content
    end
  end

  context "#valid?" do
    test "validates year is within the past 2 years" do
      year = SponsorsListing::SponsorshipsExport::START_YEAR - 1

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: year,
        month: Date::MONTHNAMES[1],
        format: :json,
      )

      refute_predicate export, :valid?
      assert_includes export.errors[:year], "#{year} is not a valid year"
    end

    test "allows nil year and month when timeframe=all" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: nil,
        month: nil,
        format: :json,
        timeframe: "all",
      )

      assert_predicate export, :valid?
    end

    test "validates month is valid" do
      month = "Fake"

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: month,
        format: :json,
      )

      refute_predicate export, :valid?
      assert_includes export.errors[:month], "#{month} is not a valid month"
    end

    test "allows nil month when timeframe=year" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: nil,
        format: :json,
        timeframe: "year",
      )

      assert_predicate export, :valid?
    end

    test "validates format is valid" do
      format = "xml"

      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: format,
      )

      refute_predicate export, :valid?
      assert_includes export.errors[:format], "#{format} is not a valid format"
    end

    test "format is case insensitive" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: "JSON",
      )

      assert_predicate export, :valid?
    end
  end

  context "#start_export_job" do
    test "enqueues the ExportSponsorshipsJob" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: Date::MONTHNAMES[1],
        format: "json",
      )

      assert_enqueued_with(job: ExportSponsorshipsJob) do
        export.start_export_job(actor: @org_admin)
      end
    end

    test "does NOT enqueue the ExportSponsorshipsJob if invalid" do
      export = SponsorsListing::SponsorshipsExport.new(
        sponsors_listing: @org_listing,
        year: SponsorsListing::SponsorshipsExport::START_YEAR,
        month: :Invalid,
        format: "json",
      )

      export.start_export_job(actor: @org_admin)

      assert_enqueued_jobs 0, only: ExportSponsorshipsJob
    end
  end
end
