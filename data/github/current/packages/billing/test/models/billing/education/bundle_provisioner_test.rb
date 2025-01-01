# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Education::BundleProvisionerTest < GitHub::BillingTestCase
  context "#perform!" do
    test "creates a sales_serve_plan_subscription if one doesn't exist" do
      business = create(:business, :with_azure_subscription)

      ::Billing::Education::BundleProvisioner.perform!(
        business: business,
        education_bundle: "plus",
        actor: create(:user)
      )

      refute_nil business.customer.sales_serve_plan_subscription
      assert_equal "plus", business.customer.sales_serve_plan_subscription.education_bundle
    end

    test "updates the education bundle when sales_serve_plan_subscription already exists" do
      business = create(:business, :with_azure_subscription)
      create(:billing_sales_serve_plan_subscription, customer: business.customer)

      ::Billing::Education::BundleProvisioner.perform!(
        business: business,
        education_bundle: "essential",
        actor: create(:user)
      )

      assert_equal "essential", business.sales_serve_plan_subscription.education_bundle
    end

    test "creates an audit log when bundle is changed" do
      events = subscribe "billing.update_education_bundle"
      actor = create(:user)
      business = create(:business, :with_azure_subscription)

      ::Billing::Education::BundleProvisioner.perform!(
        business: business,
        education_bundle: "essential",
        actor: actor
      )

      expected_payload = {
        education_bundle: "essential",
        previous_education_bundle: "none",
        business: business.slug,
        business_id: business.id,
        actor: actor.login,
        actor_id: actor.id
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not create an audit log when bundle is the same" do
      events = subscribe "billing.update_education_bundle"
      actor = create(:user)
      business = create(:business, :with_azure_subscription)
      create(:billing_sales_serve_plan_subscription, customer: business.customer, education_bundle: :essential)

      ::Billing::Education::BundleProvisioner.perform!(
        business: business,
        education_bundle: "essential",
        actor: actor
      )

      refute event = events.pop, "we expect no events"
    end

    test "returns errors when a customer is invalid" do
      business = create :business

      response = ::Billing::Education::BundleProvisioner.perform! \
        business: business,
        education_bundle: "essential"

      assert response.failed?
    end

    test "supports customers without a current plan_effective_at" do
      business = create :business, :with_azure_subscription
      business.expects(:plan_effective_at).returns nil

      response = ::Billing::Education::BundleProvisioner.perform! \
        business: business,
        education_bundle: "essential"

      assert response.success?
    end
  end
end if GitHub.billing_enabled?
