# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControls::LegalNotificationTest < GitHub::TestCase
  setup do
    skip unless GitHub.billing_enabled?
  end

  fixtures do
    @user = create :user
    @org = create :organization
    @business = create :business
  end

  context "#create_for_sponsors_maintainer" do
    test "sends an email to the legal team" do
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        TradeControls::LegalNotification.create_for_sponsors_maintainer(account: @user)
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_includes ActionMailer::Base.deliveries.last.subject, @user.login
      assert_equal ActionMailer::Base.deliveries.first.to, GitHub.trade_cela_emails
    end

    test "creates a Zendesk ticket" do
      CreateZendeskTicket.expects(:perform_later).with(
        "Trade Controls",
        "traderestrictions@noreply.github.com",
        "Sponsors - SDN True Match",
        regexp_matches(/#{@user.login}/),
        brand_id: GitHub.zendesk_brand_id,
        tags: ["squad_compliance"],
        ticket_form_id: TradeControls::LegalNotification::TRUST_AND_SAFETY_FORM_ID,
        group_id: TradeControls::LegalNotification::TRUST_AND_SAFETY_GROUP_ID,
        custom_fields: {
          GitHub.zendesk_fields[:login] => @user.login,
          GitHub.zendesk_fields[:level] => "level_2",
          GitHub.zendesk_fields[:category] => "cat_ts_trade_restrictions"
        }
      )

      TradeControls::LegalNotification.create_for_sponsors_maintainer(account: @user)
    end
  end

  context "#create_for_true_match_account" do
    test "sends an email to the support team about the true match sdn status" do
      [@user, @org, @business].each do |account|
        ActionMailer::Base.deliveries.clear
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          TradeControls::LegalNotification.create_for_true_match_account(account: account)
        end

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes ActionMailer::Base.deliveries.last.subject, account.display_login
        assert_equal ActionMailer::Base.deliveries.first.to, GitHub.true_match_notification_emails
      end
    end

    test "creates a Zendesk ticket when an account receives a true match sdn status" do
      [@user, @org, @business].each do |account|
        CreateZendeskTicket.expects(:perform_later).with(
          "Trade Controls",
          "traderestrictions@noreply.github.com",
          "SDN True Match status",
          regexp_matches(/#{account.display_login}/),
          brand_id: GitHub.zendesk_brand_id,
          tags: ["squad_t_s"],
          ticket_form_id: TradeControls::LegalNotification::TRUST_AND_SAFETY_FORM_ID,
          group_id: TradeControls::LegalNotification::TRUST_AND_SAFETY_GROUP_ID,
          custom_fields: {
            GitHub.zendesk_fields[:login] => account.display_login,
            GitHub.zendesk_fields[:level] => "level_2",
            GitHub.zendesk_fields[:category] => "cat_ts_trade_controls_msft_true_match"
          }
        )

        TradeControls::LegalNotification.create_for_true_match_account(account: account)
      end
    end
  end
end
