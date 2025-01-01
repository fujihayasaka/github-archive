# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Contact::AbstractContactDependencyTest < GitHub::TestCase
  fixtures do
    skip unless GitHub.billing_enabled?

    # Without billing information
    @user = create(:user)
    @stos_organization = create(:organization)
    @ctos_organization = create(:organization, :with_corporate_terms)
    @business = create(:business)

    # With billing information
    @user_billing_contact = {
      first_name: "Mona",
      last_name: "Lisa",
      address1: "123 Example Street",
      city: "London",
      postal_code: "LO12 3DN",
      country_code: "UK",
    }

    @entity_billing_contact = {
      entity_name: "Acme Corp",
      address1: "123 Example Street",
      city: "London",
      postal_code: "LO12 3DN",
      country_code: "UK",
    }

    @billed_user = create(:credit_card_user)
    user_contact = create(:billing_contact, customer: @billed_user.customer, **@user_billing_contact)
    user_profile = create(:account_screening_profile, :no_hit, owner: @billed_user, **@user_billing_contact)

    @billed_stos_organization = create(:organization, :organization_on_credit_card)
    @billed_stos_organization.billing_contact_link.update(id: user_contact.id)
    @billed_stos_organization.trade_screening_record_link.update(id: user_profile.id)

    @billed_ctos_organization = create(:organization, :with_corporate_terms, :organization_on_credit_card)
    create(:billing_contact, :with_org, customer: @billed_ctos_organization.customer, **@entity_billing_contact)
    create(:account_screening_profile, :no_hit, :with_org, owner: @billed_ctos_organization, **@entity_billing_contact)

    @billed_business = create(:business)
    create(:billing_contact, :with_business, customer: @billed_business.customer, **@entity_billing_contact)
    create(:account_screening_profile, :with_business, :no_hit, owner: @billed_business, **@entity_billing_contact)
  end

  # Will return the correct class when test all features is enabled
  def billing_contact_class
    GitHub.flipper[:read_billing_information_from_contacts].enabled? ? Billing::Contact : AccountScreeningProfile
  end

  context "billing_contact" do
    test "returns a new instance of billing information if a user does not have one" do
      billing_info = @user.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      refute billing_info.persisted?
    end

    test "returns the existing billing information if a user has one" do
      billing_info = @billed_user.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      assert billing_info.persisted?

      @user_billing_contact.each do |key, value|
        assert_equal value, billing_info.send(key)
      end
    end

    test "returns a new instance of billing information if a SToS org does not have one linked" do
      billing_info = @stos_organization.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      refute billing_info.persisted?
    end

    test "returns the existing linked billing information if a SToS org has one" do
      billing_info = @billed_stos_organization.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      assert billing_info.persisted?

      assert_equal @billed_user.billing_contact.id, billing_info.id

      @user_billing_contact.each do |key, value|
        assert_equal value, billing_info.send(key)
      end
    end

    test "returns a new instance of billing information if a CToS org does not have one" do
      billing_info = @ctos_organization.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      refute billing_info.persisted?
    end

    test "returns the existing billing information if a CToS org has one" do
      billing_info = @billed_ctos_organization.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      assert billing_info.persisted?

      @entity_billing_contact.each do |key, value|
        assert_equal value, billing_info.send(key)
      end
    end

    test "returns a new instance of billing information if a business does not have one" do
      billing_info = @business.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      refute billing_info.persisted?
    end

    test "returns the existing billing information if a business has one" do
      billing_info = @billed_business.billing_contact

      assert billing_info.is_a?(billing_contact_class)
      assert billing_info.persisted?

      @entity_billing_contact.each do |key, value|
        assert_equal value, billing_info.send(key)
      end
    end
  end
end
