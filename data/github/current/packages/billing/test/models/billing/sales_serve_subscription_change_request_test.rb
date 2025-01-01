# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SalesServeSubscriptionChangeRequestTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  setup do
    GitHub.context.push(actor_id: nil)
  end

  context "validations" do
    test "pass for default values" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
    end

    test "request_uuid is required" do
      change_request = build(:sales_serve_subscription_change_request, request_uuid: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:request_uuid]
    end

    test "request_uuid is generated" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
      refute_nil change_request.request_uuid
    end

    test "request_uuid is not generated if it is already set" do
      change_request = build(:sales_serve_subscription_change_request, request_uuid: "1234")

      assert_predicate(change_request, :valid?)
      assert_equal "1234", change_request.request_uuid
    end

    test "request_uuid is not generated if it is already set and read from db" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_no_changes("change_request.request_uuid") do
        change_request.save!
      end
    end

    test "request_uuid is unique" do
      change_request = create(:sales_serve_subscription_change_request)
      another_change_request = build(:sales_serve_subscription_change_request, request_uuid: change_request.request_uuid)

      refute_predicate(another_change_request, :valid?)
      assert_equal ["has already been taken"], another_change_request.errors[:request_uuid]
    end

    test "zuora_subscription_number is required" do
      change_request = build(:sales_serve_subscription_change_request, zuora_subscription_number: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:zuora_subscription_number]
    end

    test "actor is required" do
      change_request = build(:sales_serve_subscription_change_request, actor: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:actor_id]
    end

    test "customer is required" do
      change_request = build(:sales_serve_subscription_change_request, customer: nil)

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors[:customer_id]
    end

    test "items are not required" do
      change_request = build(:sales_serve_subscription_change_request)

      assert_predicate(change_request, :valid?)
    end

    test "items should be valid" do
      change_request = build(:sales_serve_subscription_change_request)
      change_request.items.build

      refute_predicate(change_request, :valid?)
      assert_equal ["can't be blank"], change_request.errors["items.change_type"]

      change_request.items.clear
      change_request.items << build(:sales_serve_subscription_change_request_item, change_request: change_request)

      assert_predicate(change_request, :valid?)
    end

    test "items are destroyed when the change request is destroyed" do
      change_request = create(:sales_serve_subscription_change_request_with_items)

      assert_difference("Billing::SalesServeSubscriptionChangeRequestItem.count", -2) do
        change_request.destroy
      end
    end
  end

  context "status" do
    test "any error items means the request is failed" do
      request = create(:sales_serve_subscription_change_request)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error)

      assert_predicate request, :failed?
      refute_predicate request, :success?
    end

    test "any pending items means the request is pending" do
      request = create(:sales_serve_subscription_change_request)
      request.items << create(:sales_serve_subscription_change_request_item, status: :pending)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)
      request.items << create(:sales_serve_subscription_change_request_item, status: :error)

      assert_predicate request, :pending?
      refute_predicate request, :success?
    end

    test "all complete items means the request is successful" do
      request = create(:sales_serve_subscription_change_request)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)

      refute_predicate request, :failed?
      refute_predicate request, :pending?
      assert_predicate request, :success?
    end

    test "any unknown items means the request is failed" do
      request = create(:sales_serve_subscription_change_request)
      request.items << create(:sales_serve_subscription_change_request_item, status: :complete)
      request.items << create(:sales_serve_subscription_change_request_item, status: :unknown)

      assert_predicate request, :failed?
      refute_predicate request, :pending?
      refute_predicate request, :success?
    end
  end

  context "#github_advanced_security_change?" do
    test "returns true if any of the items has ghas as a product" do
      change_request = create(:sales_serve_subscription_change_request)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.sample)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.sample)

      assert change_request.reload.github_advanced_security_change?
    end

    test "returns false if none of the items has ghas as a product" do
      change_request = create(:sales_serve_subscription_change_request)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.sample)

      refute change_request.reload.github_advanced_security_change?
    end
  end

  context "#github_enterprise_change?" do
    test "returns true if any of the items has ghe as a product" do
      change_request = create(:sales_serve_subscription_change_request)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.sample)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.sample)

      assert change_request.reload.github_enterprise_change?
    end

    test "returns false if none of the items has ghe as a product" do
      change_request = create(:sales_serve_subscription_change_request)
      create(:sales_serve_subscription_change_request_item, change_request: change_request, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.sample)

      refute change_request.reload.github_enterprise_change?
    end
  end

  context "#send_to_salesforce" do
    test "publishes the hydro event" do
      request = create(:sales_serve_subscription_change_request)
      product_rate_plan_charge_id = SecureRandom.hex(16)
      price = 100.0
      update_quantity = 5
      renewal_quantity = 10
      update_start_date = 1.month.from_now.change(nsec: 0)
      update_end_date = 2.months.from_now.change(nsec: 0)
      renewal_start_date = 2.months.from_now.change(nsec: 0)
      renewal_end_date = (2.months + 1.year).from_now.change(nsec: 0)
      request.items << create(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id:, price:, quantity: update_quantity, change_type: :update, start_date: update_start_date, end_date: update_end_date)
      request.items << create(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id:, price:, quantity: renewal_quantity, change_type: :renewal, start_date: renewal_start_date, end_date: renewal_end_date)
      result = request.send_to_salesforce

      assert result
      assert_hydro_published({
        request_id: request.request_uuid,
        actor: {
          name: request.actor.safe_profile_name,
          email_address: request.actor.billing_email
        },
        zuora_subscription_id: nil,
        zuora_subscription_number: request.zuora_subscription_number,
        product: [
          {
            product_rate_plan_charge_id: product_rate_plan_charge_id,
            quantity: update_quantity,
            price: price,
            start_date: update_start_date,
            end_date: update_end_date,
            type: "update",
          },
          {
            product_rate_plan_charge_id: product_rate_plan_charge_id,
            quantity: renewal_quantity,
            price: price,
            start_date: renewal_start_date,
            end_date: renewal_end_date,
            type: "renewal",
          }
        ]
      }, schema: "github.billing.v0.SalesforceSubscriptionRequest")
    end
  end if GitHub.hydro_enabled?

  context "audit log" do
    test "audit log is created when the request is created" do
      business = create(:business)
      actor = create(:user)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.create") do
        request = create(:sales_serve_subscription_change_request, customer: business.customer, actor:)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.create",
        business: business.slug,
        actor: actor.login
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log is created when the request is destroyed" do
      business = create(:business)
      request = create(:sales_serve_subscription_change_request, customer: business.customer)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.destroy") do
        request.destroy
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.destroy",
        business: business.slug,
        actor: request.actor.login,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log is created when the request is updated" do
      business = create(:business)
      request = create(:sales_serve_subscription_change_request, customer: business.customer)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.update") do
        request.touch
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.update",
        business: business.slug,
        actor: request.actor.login,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log has the actor if present on the model" do
      actor = create(:user)
      business = create(:business)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.create") do
        request = create(:sales_serve_subscription_change_request, customer: business.customer, actor: actor)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.create",
        business: business.slug,
        actor: actor.login,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log has the actor if actor_id is present on the model" do
      business = create(:business)
      actor = create(:user)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.create") do
        request = create(:sales_serve_subscription_change_request, customer: business.customer, actor_id: actor.id)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.create",
        business: business.slug,
        actor: actor.login,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log has the actor overridden if it is present in the context" do
      actor = create(:user)
      actor_override = create(:user)
      GitHub.context.push(actor: actor_override)
      business = create(:business)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.create") do
        request = create(:sales_serve_subscription_change_request, customer: business.customer, actor: actor)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.create",
        business: business.slug,
        actor: actor_override.login,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "audit log has item details" do
      business = create(:business)
      request = create(:sales_serve_subscription_change_request, customer: business.customer)
      product_rate_plan_charge_id = SecureRandom.hex(16)
      change_type = "update"
      request.items << create(:sales_serve_subscription_change_request_item, product_rate_plan_charge_id:, change_type:)
      events = assert_performed_audit_entries(count: 1, only: "sales_serve_subscription_change_request.update") do
        request.items.first.update(status: :complete)
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "sales_serve_subscription_change_request.update",
        business: business.slug,
        actor: request.actor.login,
        change_items: [{
          product: "Unknown",
          product_rate_plan_charge_id: product_rate_plan_charge_id,
          type: change_type,
          status: "complete",
        }]
      }
      assert_subset_hash expected_payload, events.first
    end
  end
end
