# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SalesManagedSubscriptionTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper

  fixtures do
    @webhook = create(:zuora_webhook, :amendment_processed)
  end

  sig { params(subscription_id: String).returns(Billing::Zuora::SalesManagedSubscription) }
  def fetch_by_subscription_id(subscription_id)
    T.must(Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(@webhook.subscription_id))
  end

  context ".fetch_by_subscription_id" do
    test "returns a new instance of a subscription when successful" do
      response = find_subscription_response(success: true)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert fetch_by_subscription_id(@webhook.subscription_id).instance_of?(Billing::Zuora::SalesManagedSubscription)
    end

    test "returns nil when fetching a zuora subscription is unsuccessful" do
      response = find_subscription_response(success: false)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_nil Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(@webhook.subscription_id)
    end
  end

  context "#enterprise?" do
    test "returns true if DotcomEntAccountId__c is set" do
      business = create(:business)
      response = find_subscription_response(business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert subscription.enterprise?
    end

    test "returns false if DotcomEntAccountId__c is not set" do
      organization = create(:organization)
      response = find_subscription_response(organization_id: organization.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      refute subscription.enterprise?
    end
  end

  context "#organization?" do
    test "returns true if DotcomOrgId__c is set" do
      business = create(:business)
      response = find_subscription_response(organization_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert subscription.organization?
    end

    test "returns false if DotcomOrgId__c is not set" do
      response = find_subscription_response(organization_id: nil)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      refute subscription.organization?
    end
  end

  context "#owner" do
    test "returns business when owner is a business" do
      business = create(:business)
      response = find_subscription_response(business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal business, subscription.owner
    end

    test "returns organization when owner is an organization" do
      organization = create(:organization)
      response = find_subscription_response(organization_id: organization.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal organization, subscription.owner
    end
  end

  context "#ensure_account_ids_match!" do
    test "does not raise if account ids match" do
      business = create(:business)
      response = find_subscription_response(business_id: business.id, account_id: business.customer.zuora_account_id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_nothing_raised do
        fetch_by_subscription_id(@webhook.subscription_id).ensure_account_ids_match!
      end
    end

    test "raises if account ids do not match" do
      business = create(:business)
      business.customer.update!(zuora_account_id: "invalid_account_id")
      response = find_subscription_response(business_id: business.id, account_id: SecureRandom.hex)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_raises Billing::Zuora::WebhookError do
        fetch_by_subscription_id(@webhook.subscription_id).ensure_account_ids_match!
      end
    end
  end

  context "#ensure_owner_invoiced!" do
    test "does not raise if owner is a business" do
      business = create(:business)
      response = find_subscription_response(business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_nothing_raised do
        fetch_by_subscription_id(@webhook.subscription_id).ensure_owner_invoiced!
      end
    end

    test "does not raise if owner is an invoiced organization" do
      organization = create(:invoiced_organization)
      response = find_subscription_response(organization_id: organization.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_nothing_raised do
        fetch_by_subscription_id(@webhook.subscription_id).ensure_owner_invoiced!
      end
    end

    test "raises if owner is a non-invoiced organization" do
      organization = create(:credit_card_organization)
      response = find_subscription_response(organization_id: organization.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_raises Billing::Zuora::WebhookError do
        fetch_by_subscription_id(@webhook.subscription_id).ensure_owner_invoiced!
      end
    end
  end

  context "#id" do
    test "delegates to zuora subscription's id" do
      business = create(:business)
      response = find_subscription_response(id: "123", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "123", subscription.id
    end
  end

  context "#account_id" do
    test "delegates to zuora subscription's accountId" do
      business = create(:business)
      response = find_subscription_response(account_id: "123", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "123", subscription.account_id
    end
  end

  context "#account_number" do
    test "delegates to zuora subscription's accountNumber" do
      business = create(:business)
      response = find_subscription_response(account_number: "12345", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "12345", subscription.account_number
    end
  end

  context "#subscription_number" do
    test "delegates to zuora subscription's subscriptionNumber" do
      business = create(:business)
      response = find_subscription_response(subscription_number: "12345", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "12345", subscription.subscription_number
    end
  end

  context "#term_end_date" do
    test "returns termEndDate as a date if present" do
      business = create(:business)
      response = find_subscription_response(term_end_date: "2019-01-30", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal Date.parse("2019-01-30"), subscription.term_end_date
    end

    test "returns nil if termEndDate is not present" do
      business = create(:business)
      response = find_subscription_response(term_end_date: "", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.term_end_date
    end
  end

  context "#term_start_date" do
    test "returns termStartDate as a date if present" do
      business = create(:business)
      response = find_subscription_response(start_date: Date.parse("2019-01-30"), business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal Date.parse("2019-01-30"), subscription.term_start_date
    end

    test "returns nil if termStartDate is not present" do
      Zuorest::Model::Subscription
        .expects(:find)
        .with(@webhook.subscription_id)
        .returns(Zuorest::Model::Subscription.new({
          termStartDate: "",
          success: true,
        }))

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.term_start_date
    end
  end

  context "#license_number" do
    test "returns licenseNumber if present" do
      business = create(:business)
      response = find_subscription_response(license_number: "test-license-number")
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "test-license-number", subscription.license_number
    end

    test "returns nil if licenseNumber is not present" do
      Zuorest::Model::Subscription
        .expects(:find)
        .with(@webhook.subscription_id)
        .returns(Zuorest::Model::Subscription.new({
          success: true,
        }))

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.license_number
    end
  end

  context "#seats" do
    test "returns seats from multiple rate plan charges ignoring LFS, refills and VSS SKUs" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: nil, quantity: "", Provisionable_Quantity__c: "25"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: "13", Provisionable_Quantity__c: nil),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: "300", Provisionable_Quantity__c: "100"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, id: SecureRandom.hex, productRatePlanChargeId: GitHub.zuora_metered_refill_rate_plan_charge_ids.first, price: 100.00, currency: "USD", Provisionable_Quantity__c: "150"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "no_dotcom_plan", Provisionable_Quantity__c: "1000"),
          ]),
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal 40, subscription.seats
    end
  end

  context "#plan" do
    test "returns plan in rate plan charges when present" do
      business = create(:business)
      response = find_subscription_response(plan_name: "business_plus", business_id: business.id)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal "business_plus", subscription.plan
    end

    test "returns nil if no plan is present" do
      response = find_subscription_response(rate_plans: [])
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.plan
    end
  end

  context "#data_packs" do
    test "returns total number of data packs purchased across rate plan charges" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: nil, quantity: 51, Provisionable_Quantity__c: "25"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: 13, Provisionable_Quantity__c: nil),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: 300, Provisionable_Quantity__c: "100"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: 300, Provisionable_Quantity__c: "100"),
          ]),
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal 600, subscription.data_packs
    end
  end

  context "#active_usage_refill_rate_plan_charges" do
    test "returns an array of prepaid usage refill rate charges" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: nil, quantity: "51", Provisionable_Quantity__c: "25"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: "13", Provisionable_Quantity__c: nil),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: "300", Provisionable_Quantity__c: "100"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: "300", Provisionable_Quantity__c: "100"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_metered_refill_rate_plan_charge_ids.first, price: 100.00, currency: "USD"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_metered_refill_rate_plan_charge_ids.first, price: 100.01, currency: "USD", effectiveStartDate: "2020-08-31", effectiveEndDate: "2020-08-31"),
          ]),
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_equal 1, subscription.active_usage_refill_rate_plan_charges.length
      assert_equal 100.0, T.must(subscription.active_usage_refill_rate_plan_charges.first)[:price]
    end
  end

  context "#sales_serve_actions_rate_plan_charge" do
    test "returns the actions rate plan charge" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: "13", Provisionable_Quantity__c: nil),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_lfs_rate_plan_charge_ids.first, quantity: "300", Provisionable_Quantity__c: "100"),
          ]),
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_actions_product_charge_ids.first, quantity: "30000", includedUnits: 123456),
          ]),
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      actions_rate_plan_charge = T.must(subscription.sales_serve_actions_rate_plan_charge)
      assert_equal actions_rate_plan_charge.product_rate_plan_charge_id,
        GitHub.zuora_sales_serve_actions_product_charge_ids.first
      assert_equal actions_rate_plan_charge.included_units, 123456
    end

    test "returns nil when an actions rate plan charge doesn't exist" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: "13", Provisionable_Quantity__c: nil),
          ]),
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.sales_serve_actions_rate_plan_charge
    end
  end

  context "#metered_ghec?" do
    test "returns true when the list of rate plan charges contains a charge with IsMetered__c" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", IsMetered__c: true),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert subscription.metered_ghec?
    end

    test "returns false when the list of rate plan charges does not contain a charge with IsMetered__c" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      refute subscription.metered_ghec?
    end
  end

  context "#education_bundle_rate_plan_charge" do
    test "returns the Education Bundle rate plan charge" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, BundlePlan__c: "essential", Plan_Name__c: "business_plus"),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      education_rate_plan_charge = T.must(subscription.education_bundle_rate_plan_charge)
      assert_equal education_rate_plan_charge.bundle_plan, "essential"
    end

    test "returns nil when there's no Education Bundle rate plan charge" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "business_plus", quantity: 15, Provisionable_Quantity__c: "15"),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, Plan_Name__c: "", quantity: "13", Provisionable_Quantity__c: nil),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      education_rate_plan_charge = subscription.education_bundle_rate_plan_charge
      refute education_rate_plan_charge
    end
  end

  context "#ghe_rate_plan_charge" do
    test "returns the GHE rate plan charge" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 100.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 300.0),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      ghe_rate_plan_charge = T.must(subscription.ghe_rate_plan_charge)
      assert_equal ghe_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghe_product_charge_ids.first
      assert_equal ghe_rate_plan_charge.price, 100.0
    end

    test "returns the GHE rate plan charge that's not in the future" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 100.0, effectiveStartDate: 1.month.from_now.strftime("%Y-%m-%d")),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 300.0, effectiveStartDate: 1.month.from_now.strftime("%Y-%m-%d")),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      ghe_rate_plan_charge = T.must(subscription.ghe_rate_plan_charge)
      assert_equal ghe_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghe_product_charge_ids.first
      assert_equal ghe_rate_plan_charge.price, 200.0
    end

    test "returns nil when the GHE rate plan charge does not exist" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 100.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 300.0),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.ghe_rate_plan_charge
    end
  end

  context "#ghas_rate_plan_charge" do
    test "returns the GHAS rate plan charge" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 100.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 300.0),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      ghas_rate_plan_charge = T.must(subscription.ghas_rate_plan_charge)
      assert_equal ghas_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghas_product_charge_ids.first
      assert_equal ghas_rate_plan_charge.price, 100.0
    end

    test "returns the GHAS rate plan charge that's not in the future" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 100.0, effectiveStartDate: 1.month.from_now.strftime("%Y-%m-%d")),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, price: 300.0, effectiveStartDate: 1.month.from_now.strftime("%Y-%m-%d")),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      ghas_rate_plan_charge = T.must(subscription.ghas_rate_plan_charge)
      assert_equal ghas_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghas_product_charge_ids.first
      assert_equal ghas_rate_plan_charge.price, 200.0
    end

    test "returns nil when the GHAS rate plan charge does not exist" do
      response = find_subscription_response(
        rate_plans: [
          FactoryBot.attributes_for(:zuora_rate_plan, ratePlanCharges: [
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 100.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 200.0),
            FactoryBot.attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, price: 300.0),
          ])
        ]
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      subscription = fetch_by_subscription_id(@webhook.subscription_id)

      assert_nil subscription.ghas_rate_plan_charge
    end
  end
end if GitHub.billing_enabled?
