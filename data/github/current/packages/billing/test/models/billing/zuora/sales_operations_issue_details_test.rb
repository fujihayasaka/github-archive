# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SalesOperationsIssueDetailsTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper

  context "#generate" do
    test "returns an empty hash if not a sales serve webhook" do
      payment_processed = create(:zuora_webhook, :payment_processed)
      details = Billing::Zuora::SalesOperationsIssueDetails.new(payment_processed)

      assert_equal({}, details.generate)
    end

    test "returns an empty hash if there's no customer record for the Zuora account" do
      webhook = create(:zuora_webhook, :subscription_created)
      business = create(:business, customer: nil)
      organization = create(:organization)
      business.add_organization(organization)

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: "account_id",
        account_number: "account_number",
        organization_id: nil,
        business_id: business.id,
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook)

      assert_equal({}, details.generate)
    end

    test "returns an empty hash and does not raise an error if the organization or enterprise account referred to by the Zuora subscription does not exist" do
      webhook = create(:zuora_webhook, :subscription_created)
      customer = create(:no_credit_card_customer)

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: customer.zuora_account_id,
        account_number: customer.zuora_account_number,
        organization_id: nil,
        business_id: "some bogus data",
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook)

      assert_equal({}, details.generate)
    end

    test "returns a hash of important details when given a subscription_created webhook when the subscription is linked to an organization" do
      webhook = create(:zuora_webhook, :subscription_created)
      customer = create(:no_credit_card_customer)
      business = create(:business, customer: customer)
      organization = create(:organization)

      business.add_organization(organization)

      original_zuora_account_id = customer.zuora_account_id
      original_zuora_account_number = customer.zuora_account_number

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: original_zuora_account_id,
        account_number: original_zuora_account_number,
        organization_id: organization.id,
        business_id: nil,
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      generated_details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook).generate

      assert_equal %i(ask description links new_issue_link title), generated_details.keys.sort
      assert_equal "https://github.com/github/sales-operations/issues/new?labels=sales-support%2C+Priority+-+To+Be+Triaged&template=25+-+Standard+Issue.md&title=Standard+Issue", generated_details[:new_issue_link]
      assert_equal "#{organization.login} (Organization) #{webhook.kind} webhook unable to be processed due to re-used zuora account id", generated_details[:title]
      assert_match organization.login, generated_details[:description]
      assert_match business.slug, generated_details[:description]
      assert_equal "How should these accounts be associated to each other and/or Zuora?", generated_details[:ask]
      assert_equal 3, generated_details[:links].count
      assert_match "#{business.slug} (Enterprise Account) Zuora", generated_details[:links].join(",")
      assert_match "#{organization.login} (Organization) stafftools", generated_details[:links].join(",")
      assert_match "#{business.slug} (Enterprise Account) stafftools", generated_details[:links].join(",")
    end

    test "returns a hash of important details when given a subscription_created webhook when the subscription is linked to a business" do
      webhook = create(:zuora_webhook, :subscription_created)
      business = create(:business, customer: nil)
      organization = create(:organization)

      customer = create(:no_credit_card_customer)
      customer.organizations << organization
      business.add_organization(organization)

      original_zuora_account_id = customer.zuora_account_id
      original_zuora_account_number = customer.zuora_account_number

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: original_zuora_account_id,
        account_number: original_zuora_account_number,
        organization_id: nil,
        business_id: business.id,
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      generated_details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook).generate

      assert_equal %i(ask description links new_issue_link title), generated_details.keys.sort
      assert_equal "https://github.com/github/sales-operations/issues/new?labels=sales-support%2C+Priority+-+To+Be+Triaged&template=25+-+Standard+Issue.md&title=Standard+Issue", generated_details[:new_issue_link]
      assert_equal "#{business.slug} (Enterprise Account) #{webhook.kind} webhook unable to be processed due to re-used zuora account id", generated_details[:title]
      assert_match organization.login, generated_details[:description]
      assert_match business.slug, generated_details[:description]
      assert_equal "How should these accounts be associated to each other and/or Zuora?", generated_details[:ask]
      assert_equal 3, generated_details[:links].count
      assert_match "#{organization.login} (Organization) Zuora", generated_details[:links].join(",")
      assert_match "#{organization.login} (Organization) stafftools", generated_details[:links].join(",")
      assert_match "#{business.slug} (Enterprise Account) stafftools", generated_details[:links].join(",")
    end

    test "can be converted to a pretty string" do
      webhook = create(:zuora_webhook, :subscription_created)
      business = create(:business, customer: nil)
      organization = create(:organization)

      customer = create(:no_credit_card_customer)
      customer.organizations << organization
      business.add_organization(organization)

      original_zuora_account_id = customer.zuora_account_id
      original_zuora_account_number = customer.zuora_account_number

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: original_zuora_account_id,
        account_number: original_zuora_account_number,
        organization_id: nil,
        business_id: business.id,
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook)

      assert_equal <<~EOF, details.to_s
      Link:
      https://github.com/github/sales-operations/issues/new?labels=sales-support%2C+Priority+-+To+Be+Triaged&template=25+-+Standard+Issue.md&title=Standard+Issue

      Title:
      #{business.slug} (Enterprise Account) #{webhook.kind} webhook unable to be processed due to re-used zuora account id

      Description:
      We received a Zuora webhook targeting #{business.slug} (Enterprise Account). It is already in use for the #{organization.login} (Organization). Webhook ID for future @github/gitcoin first responder: #{webhook.id}

      Ask:
      How should these accounts be associated to each other and/or Zuora?

      Links:
      [#{organization.login} (Organization) Zuora](#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}) - [#{organization.login} (Organization) stafftools](https://admin.github.com/stafftools/users/#{organization.login}) - [#{business.slug} (Enterprise Account) stafftools](https://admin.github.com/stafftools/enterprises/#{business.slug})
      EOF
    end

    test "does not generate an error when converting to a pretty string when the webhook doesn't have an existing customer" do
      webhook = create(:zuora_webhook, :subscription_created)
      business = create(:business, customer: nil)
      organization = create(:organization)
      business.add_organization(organization)

      subscription = find_subscription_response(
        success: true,
        id: webhook.subscription_id,
        account_id: "account_id",
        account_number: "account_number",
        organization_id: nil,
        business_id: business.id,
        plan_name: "business_plus",
        subscription_number: SecureRandom.hex,
        start_date: GitHub::Billing.today,
      )

      Zuorest::Model::Subscription.expects(:find).with(webhook.subscription_id).returns(subscription).at_least_once

      details = Billing::Zuora::SalesOperationsIssueDetails.new(webhook)

      assert_equal("", details.to_s)
    end
  end
end if GitHub.billing_enabled?
