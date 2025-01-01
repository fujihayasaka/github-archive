# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::InvoicedSponsorAccountCreatorTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include HydroTestHelpers

  fixtures do
    @org = create(:credit_card_organization)
    create(:organization_profile, organization: @org)
    @name = "Test Org"
    @address = {
      line1: "123 Main Street",
      line2: "",
      city: "New York City",
      state: "NY",
      postal_code: "12345",
      country: "US",
    }
    @email = "testorg@test.com"
  end

  context "#call" do
    test "instruments Sponsors-invoiced account creation", skip_unless: :sponsors_enabled? do

      stripe_customer_id = "cus_NkIRYhDKH3PU6v"
      mock_billing_customer_create
      mock_stripe_customer_create(customer_id: stripe_customer_id)

      creator = Sponsors::InvoicedSponsorAccountCreator.new(
        org: @org,
        name: @name,
        address: @address,
        email: @email,
        actor: @org.admin
      )

      perform_enqueued_jobs only: InitializeInvoicedSponsorJob do
        creator.call
      end

      expected_message = {
        organization: Hydro::EntitySerializer.organization(@org),
        actor: Hydro::EntitySerializer.user(@org.admin),
        stripe_customer_id: stripe_customer_id,
      }

      assert_equal stripe_customer_id, @org.stripe_customer_id
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeCustomerCreate")
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeCustomerCreate")
    end
  end

  context "#setup" do
    if GitHub.sponsors_enabled?
      test "sets up invoiced sponsors accounts with given information for org" do
        mock_billing_customer_create
        mock_stripe_customer_create(customer_id: "cus_NkIRYhDKH3PU6v")

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: @email,
        )

        assert creator.setup
        assert_empty creator.errors
        assert_equal "cus_NkIRYhDKH3PU6v", @org.stripe_customer_id
      end

      test "cancels existing sponsorships and closes out zuora plan subscription" do
        sponsorship = create(:sponsorship, sponsor: @org)
        assert_predicate sponsorship, :active?

        mock_billing_customer_create

        close_subscription_mock = Minitest::Mock.new
        close_subscription_mock.expect(:success?, true)
        ::Billing::CloseZuoraSubscription.expects(:perform).once.with(
          zuora_subscription_number: @org.sponsors_plan_subscription.zuora_subscription_number,
          plan_subscription: @org.sponsors_plan_subscription,
        ).returns(close_subscription_mock)

        mock_stripe_customer_create(customer_id: "cus_NkIRYhDKH3PU6v")

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: @email,
        )

        assert creator.setup
        assert_empty creator.errors
        assert_equal "cus_NkIRYhDKH3PU6v", @org.stripe_customer_id
        refute_predicate sponsorship.reload, :active?
      end

      test "instruments sponsorship cancellation request to Hydro" do
        GitHub.flipper[:sponsors_self_serve_invoice_creation].enable(@org)

        sponsorship = create(:sponsorship, sponsor: @org)
        assert_predicate sponsorship, :active?

        create_customer_mock = Minitest::Mock.new
        create_customer_mock.expect(:success?, true)
        ::Billing::CreateCustomer.expects(:perform).once.with(@org, details: {
          omit_billing_info: true,
        }, purpose: :sponsors).returns(create_customer_mock)

        close_subscription_mock = Minitest::Mock.new
        close_subscription_mock.expect(:success?, true)
        ::Billing::CloseZuoraSubscription.expects(:perform).once.with(
          zuora_subscription_number: @org.sponsors_plan_subscription.zuora_subscription_number,
          plan_subscription: @org.sponsors_plan_subscription,
        ).returns(close_subscription_mock)

        stripe_args = {
          name: @name,
          address: @address,
          email: @email,
          shipping: {
            name: @name,
            address: @address,
          },
        }
        customer_response = { id: "cus_NkIRYhDKH3PU6v" }.merge(stripe_args)
        Stripe::Customer.expects(:create).with(equals(stripe_args)).returns(Stripe::Customer.construct_from(customer_response))

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: @email,
        )

        expected_message = {
          request_context: nil,
          sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
          tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
          listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
          listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
            sponsorship.sponsors_listing_stafftools_metadata,
          ),
          actor: Hydro::EntitySerializer.user(User.staff_user),
          sponsor: Hydro::EntitySerializer.user(@org),
          sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
          reason: :INVOICED_SPONSOR_CREATED,
          forced: true
        }
        assert creator.setup
        assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      end

      test "setup" do
        synchronize_github_products_to_zuora

        GitHub::Plan.any_instance.expects(:zuora_charge_ids).at_least_once.with(cycle: "month").returns(
          base_unit: "123_base_unit",
          unit: "123_unit",
          annual_discount: "123_charge_id"
        )
        with_live_zuora("sponsors/invoiced_sponsor_account_creator") do
          customer = @org.customer
          customer.update!(
            zuora_account_id: "8ad08d2986bb64550186befc32945e75",
            zuora_account_number: "A0102179575",
          )
          sponsorship = create(:sponsorship, sponsor: @org)
          sponsors_plan_subscription = @org.sponsors_plan_subscription
          sponsorship.sponsors_listing.sync_to_zuora

          synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_subscription, false,
            collect: false,
          )
          synchronizer.create

          zuora_subscription = sponsors_plan_subscription.reload.zuora_subscription

          assert_predicate sponsorship, :active?
          assert_nil @org.stripe_customer_id
          assert_nil @org.sponsors_customer

          creator = Sponsors::InvoicedSponsorAccountCreator.new(
            org: @org,
            name: @name,
            address: @address,
            email: @email,
          )

          assert creator.setup

          assert_empty creator.errors
          assert @org.sponsors_customer # Sponsors-purpose customer created
          refute_nil @org.stripe_customer_id # stripe customer created
          refute_predicate sponsorship.reload, :active? # sponsorship canceled
          zuora_subscription = Billing::Zuora::Subscription.find(zuora_subscription.id)
          refute_predicate zuora_subscription, :active? # Zuora subscription canceled
        end
      end

      test "requires name" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: "",
          address: @address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Name can't be blank"], creator.errors.full_messages
      end

      test "requires email not to be blank" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: "",
        )

        refute creator.setup
        assert_equal ["Email must be a valid email address"], creator.errors.full_messages
      end

      test "requires email to look like a valid email" do
        Stripe::Customer.expects(:create).never

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: "jisoo@",
        )

        refute creator.setup
        assert_equal ["Email must be a valid email address"], creator.errors.full_messages
      end

      test "address requires line1" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ line1: "" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address line1 can't be blank"], creator.errors.full_messages
      end

      test "address requires city" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ city: "" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address city can't be blank"], creator.errors.full_messages
      end

      test "address requires a valid country code" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ country: "ABC" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address country must be a valid country code"], creator.errors.full_messages
      end

      test "address requires a country code that is not sanctioned" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ country: "KP" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address country must be a valid country code"], creator.errors.full_messages
      end

      test "address requires a postal code for certain countries" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        country_code = ::TradeControls::Countries::POSTAL_CODE_REQUIRED_GEOS.sample
        address = @address.merge({ country: country_code, postal_code: "" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address postal code can't be blank"], creator.errors.full_messages
      end

      test "address requires a state for US" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ state: "" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address state can't be blank"], creator.errors.full_messages
      end

      test "address requires a state for CA" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        address = @address.merge({ country: "CA", state: "" })

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["Address state can't be blank"], creator.errors.full_messages
      end

      test "address does not require state for random country" do
        address = @address.merge({ city: "Ciudad de Mexico", country: "MX", state: "" })

        mock_billing_customer_create
        mock_stripe_customer_create(
          customer_id: "cus_O7SbdmPlN8Krq7",
          stripe_arg_overrides: {
            address: address,
            shipping: {
              name: @name,
              address: address
            }
          }
        )

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: address,
          email: @email,
        )

        assert creator.setup
        assert_empty creator.errors
        assert_equal "cus_O7SbdmPlN8Krq7", @org.stripe_customer_id
      end
    else
      test "requires Sponsors to be a feature" do
        Stripe::Customer.expects(:create).never
        Billing::CreateCustomer.expects(:perform).never

        creator = Sponsors::InvoicedSponsorAccountCreator.new(
          org: @org,
          name: @name,
          address: @address,
          email: @email,
        )

        refute creator.setup
        assert_equal ["GitHub Sponsors is not an available feature"], creator.errors.full_messages
      end
    end
  end

  def mock_billing_customer_create
    billing_mock = Minitest::Mock.new
    billing_mock.expect(:success?, true)
    ::Billing::CreateCustomer.expects(:perform).once.with(@org, details: {
      omit_billing_info: true,
    }, purpose: :sponsors).returns(billing_mock)
  end

  def mock_stripe_customer_create(customer_id:, stripe_arg_overrides: {})
    stripe_args = {
      name: @name,
      address: @address,
      email: @email,
      shipping: {
        name: @name,
        address: @address,
      },
    }.merge(stripe_arg_overrides)
    customer_response = { id: customer_id }.merge(stripe_args)
    Stripe::Customer.expects(:create).with(equals(stripe_args)).returns(Stripe::Customer.construct_from(customer_response))
  end
end
