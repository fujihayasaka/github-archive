# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::InvoicedMeteredBillingSlackNotifierTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @organization = create(:invoiced_organization, plan: "business", admins: [@user])
    @business = create(:business, owners: [@user])
  end

  setup do
    @chatterbox_client = mock("Client")
    GitHub::Chatterbox.stubs(client: @chatterbox_client)
  end

  context "#send_notification" do
    context "paid is true" do
      test "calls chatterbox with correct slack channel and message for organization" do
        @chatterbox_client.expects(:say).once.with(
          Billing::InvoicedMeteredBillingSlackNotifier::THRESHOLD_NOTIFICATION_SLACK_CHANNEL,
          "[Paid Usage Alert] <https://admin.github.com/stafftools/users/#{@organization.login}|#{@organization.name}> hello from the other side\nMeter resets on: #{@organization.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
        )

        Billing::InvoicedMeteredBillingSlackNotifier.new(
          owner: @organization,
          paid: true,
          usage_message: "hello from the other side"
        ).send_notification
      end

      test "calls chatterbox with correct slack channel and message for business" do
        @chatterbox_client.expects(:say).once.with(
          Billing::InvoicedMeteredBillingSlackNotifier::THRESHOLD_NOTIFICATION_SLACK_CHANNEL,
          "[Paid Usage Alert] <https://admin.github.com/stafftools/enterprises/#{@business.slug}|#{@business.name}> hello from the other side\nMeter resets on: #{@business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
        )

        Billing::InvoicedMeteredBillingSlackNotifier.new(
          owner: @business,
          paid: true,
          usage_message: "hello from the other side"
        ).send_notification
      end
    end

    test "calls chatterbox with correct slack channel and message for business" do
      @chatterbox_client.expects(:say).once.with(
        Billing::InvoicedMeteredBillingSlackNotifier::THRESHOLD_NOTIFICATION_SLACK_CHANNEL,
        "[Paid Usage Alert] <https://admin.github.com/stafftools/enterprises/#{@business.slug}|#{@business.name}> hello from the other side\nMeter resets on: #{@business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
      )

      Billing::InvoicedMeteredBillingSlackNotifier.new(
        owner: @business,
        paid: true,
        usage_message: "hello from the other side"
      ).send_notification
    end

    context "paid is false" do
      test "calls chatterbox with correct slack channel and message for organization" do
        @chatterbox_client.expects(:say).once.with(
          Billing::InvoicedMeteredBillingSlackNotifier::THRESHOLD_NOTIFICATION_SLACK_CHANNEL,
          "[Included Free Usage Alert] <https://admin.github.com/stafftools/users/#{@organization.login}|#{@organization.name}> hello from the other side\nMeter resets on: #{@organization.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
        )

        Billing::InvoicedMeteredBillingSlackNotifier.new(
          owner: @organization,
          paid: false,
          usage_message: "hello from the other side"
        ).send_notification
      end

      test "calls chatterbox with correct slack channel and message for business" do
        @chatterbox_client.expects(:say).once.with(
          Billing::InvoicedMeteredBillingSlackNotifier::THRESHOLD_NOTIFICATION_SLACK_CHANNEL,
          "[Included Free Usage Alert] <https://admin.github.com/stafftools/enterprises/#{@business.slug}|#{@business.name}> hello from the other side\nMeter resets on: #{@business.next_metered_billing_cycle_starts_at.to_date.to_formatted_s(:long)}"
        )

        Billing::InvoicedMeteredBillingSlackNotifier.new(
          owner: @business,
          paid: false,
          usage_message: "hello from the other side"
        ).send_notification
      end
    end
  end
end if GitHub.billing_enabled?
