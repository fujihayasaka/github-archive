# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::TradeCompliance::ContactDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include ::TradeCompliance::TradeScreening::TradeScreeningTestHelpers

  fixtures do
    skip unless GitHub.billing_enabled?

    @user = create(:credit_card_user)
    @org = create(:credit_card_org)
    @business = create(:business)
  end

  context "#trade_screening_request_id" do
    test "returns hardcoded value for individual billing contact" do
      contact = create(:billing_contact)

      assert_predicate contact, :valid?
      assert_equal "IndName_IndAddr", contact.trade_screening_request_id
    end

    test "returns hardcoded value for entity billing contact" do
      contact = create(:billing_contact, :with_org)

      assert_predicate contact, :valid?
      assert_equal "OrgName_OrgAddr", contact.trade_screening_request_id
    end

    test "doesn't return hardcoded value for individual shipping contact" do
      contact = create(:shipping_contact)

      assert_predicate contact, :valid?
      assert_equal contact.id.to_s, contact.trade_screening_request_id
    end

    test "doesn't return hardcoded value for entity shipping contact" do
      contact = create(:shipping_contact, :with_org)

      assert_predicate contact, :valid?
      assert_equal contact.id.to_s, contact.trade_screening_request_id
    end
  end

  context "#customer_details" do
    test "returns details for billing contact" do
      contact = T.let(create(:billing_contact), Billing::Contact)
      expected_customer_details = ::TradeCompliance::TradeScreening::CustomerDetails.new(
        id: "IndName_IndAddr",
        first_name: contact.first_name,
        last_name: contact.last_name,
        entity_name: contact.entity_name,
        vat_code: T.must(contact.customer).vat_code,
        address1: contact.address1,
        address2: contact.address2,
        city: contact.city,
        region: contact.region,
        country_code: contact.country_code,
        postal_code: contact.postal_code
      )

      customer_details = contact.customer_details

      assert_customer_details_equal expected_customer_details, customer_details
    end

    test "returns details for shipping contact" do
      contact = T.let(create(:shipping_contact), Billing::Contact)
      expected_customer_details = ::TradeCompliance::TradeScreening::CustomerDetails.new(
        id: contact.id.to_s,
        first_name: contact.first_name,
        last_name: contact.last_name,
        entity_name: contact.entity_name,
        vat_code: T.must(contact.customer).vat_code,
        address1: contact.address1,
        address2: contact.address2,
        city: contact.city,
        region: contact.region,
        country_code: contact.country_code,
        postal_code: contact.postal_code
      )

      customer_details = contact.customer_details

      assert_customer_details_equal expected_customer_details, customer_details
    end
  end

  %i[billing_contact shipping_contact].each do |address_type|
    context "#individual_trade_screening_validations for #{address_type}" do
      test "first name must be present" do
        contact = build(address_type, customer: @user.customer, first_name: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "First name can't be blank"
      end

      test "last name must be present" do
        contact = build(address_type, customer: @user.customer, last_name: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "Last name can't be blank"
      end

      test "address1 must be present" do
        contact = build(address_type, address1: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "Address can't be blank"
      end

      test "address2 can be blank" do
        contact = create(address_type, address2: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :individual_trade_screening)
      end

      test "city must be present" do
        contact = build(:billing_contact, city: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "City can't be blank"
      end

      test "postal code must be present for country where required" do
        contact = build(:billing_contact, country_code: "US", postal_code: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "Postal/Zip code can't be blank"
      end

      test "postal code can be blank for country where not required" do
        contact = create(:billing_contact, country_code: "IE", postal_code: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :individual_trade_screening)
      end

      test "country code must be present" do
        contact = build(:billing_contact, country_code: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "Country/Region can't be blank"
      end

      test "region must be present for country where required" do
        contact = build(:billing_contact, country_code: "US", region: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :individual_trade_screening)
        assert_includes contact.errors.full_messages, "State/Province can't be blank"
      end

      test "region can be blank for country where not required" do
        contact = create(:billing_contact, country_code: "IE", region: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :individual_trade_screening)
      end
    end

    context "#entity_trade_screening_validations for #{address_type}" do
      test "entity name must be present for business" do
        contact = build(address_type, :with_business, customer: @business.customer, entity_name: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "Business/Institution name can't be blank"
      end

      test "address1 must be present" do
        contact = build(address_type, :with_business, address1: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "Address can't be blank"
      end

      test "address2 can be blank" do
        contact = create(address_type, :with_business, address2: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :entity_trade_screening)
      end

      test "city must be present" do
        contact = build(address_type, :with_business, city: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "City can't be blank"
      end

      test "postal code must be present for country where required" do
        contact = build(address_type, :with_business, country_code: "US", postal_code: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "Postal/Zip code can't be blank"
      end

      test "postal code can be blank for country where not required" do
        contact = create(address_type, :with_business, country_code: "IE", postal_code: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :entity_trade_screening)
      end

      test "country code must be present" do
        contact = build(address_type, :with_business, country_code: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "Country/Region can't be blank"
      end

      test "region must be present for country where required" do
        contact = build(address_type, :with_business, country_code: "US", region: "")

        assert_predicate contact, :valid?
        refute contact.valid?(context: :entity_trade_screening)
        assert_includes contact.errors.full_messages, "State/Province can't be blank"
      end

      test "region can be blank for country where not required" do
        contact = create(address_type, :with_business, country_code: "IE", region: "")

        assert_predicate contact, :valid?
        assert contact.valid?(context: :entity_trade_screening)
      end
    end
  end
end
