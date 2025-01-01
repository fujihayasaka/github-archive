# typed: true
# frozen_string_literal: true

require "test_helper"

class Customer::ContactDependencyTest < GitHub::TestCase
  fixtures do
    skip unless GitHub.billing_enabled?
  end

  context "#billing_contact" do
    [:credit_card_user, :credit_card_org, :business].each do |factory|
      test "returns existing contact for #{factory}" do
        traits = :with_corporate_terms if factory == :credit_card_org
        account = create(factory, traits)
        contact = create(:billing_contact, customer: account.customer)

        assert_predicate account.customer.billing_contact, :persisted?

        assert_equal contact.id, account.customer.billing_contact.id
      end

      test "returns dirty contact when it's not saved yet for #{factory}" do
        account = create(factory)
        account.customer.billing_contact.first_name = "John"

        refute_predicate account.customer.billing_contact, :persisted?

        assert_equal "John", account.customer.billing_contact.first_name
      end

      test "returns blank contact when it doesn't exist for #{factory}" do
        account = create(factory)

        refute_predicate account.customer.billing_contact, :persisted?

        assert_predicate account.customer.billing_contact.id, :nil?
      end
    end

    test "returns existing linked contact for standard terms org" do
      user = create(:credit_card_user)
      contact = create(:billing_contact, customer: user.customer)
      org = create(:credit_card_org, admin: user)
      assert org.link_billing_contact(actor: user)

      assert_predicate org.customer.billing_contact, :persisted?

      assert_equal contact.id, org.customer.billing_contact.id
    end

    test "returns existing linked contact and memoizes result for standard terms org" do
      user = create(:credit_card_user)
      contact = create(:billing_contact, customer: user.customer)
      org = create(:credit_card_org, admin: user)
      assert org.link_billing_contact(actor: user)

      assert_predicate org.customer.billing_contact, :persisted?

      assert_equal contact.id, org.customer.billing_contact.id
      assert_no_queries do
        assert_predicate org.customer.billing_contact, :persisted?
        assert_predicate org.customer.billing_contact, :persisted?
      end
    end

    test "returns blank contact when it doesn't exist for standard terms org" do
      organization = create(:credit_card_org)

      refute_predicate organization.customer.billing_contact, :persisted?

      assert_predicate organization.customer.billing_contact.id, :nil?
    end

    test "returns blank contact when billable owner doesn't exist" do
      organization = create(:credit_card_org)
      organization.customer.stubs(:billable_owner).returns(organization).then.returns(nil)

      # first call to billing_contact checks billable_owner in #linked_billing_contact
      refute_predicate organization.customer.billing_contact, :persisted?
      # second call to billing_contact checks billable_owner in #billing_contact
      refute_predicate organization.customer.billing_contact, :persisted?

      assert_predicate organization.customer.billing_contact.id, :nil?
    end
  end

  context "#shipping_contact" do
    [:credit_card_user, :credit_card_org, :business].each do |factory|
      test "returns existing contact for #{factory}" do
        traits = :with_corporate_terms if factory == :credit_card_org
        account = create(factory, traits)
        contact = create(:shipping_contact, customer: account.customer)

        assert_predicate account.customer.shipping_contact, :persisted?

        assert_equal contact.id, account.customer.shipping_contact.id
      end

      test "returns dirty contact when it's not saved yet for #{factory}" do
        account = create(factory)
        account.customer.shipping_contact.first_name = "John"

        refute_predicate account.customer.shipping_contact, :persisted?

        assert_equal "John", account.customer.shipping_contact.first_name
      end

      test "returns blank contact when it doesn't exist for #{factory}" do
        account = create(factory)

        refute_predicate account.customer.shipping_contact, :persisted?

        assert_predicate account.customer.shipping_contact.id, :nil?
      end
    end

    test "returns blank contact when it doesn't exist for standard terms org" do
      organization = create(:credit_card_org)

      refute_predicate organization.customer.shipping_contact, :persisted?

      assert_predicate organization.customer.shipping_contact.id, :nil?
    end
  end

end
