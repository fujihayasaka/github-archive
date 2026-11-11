# typed: true
# frozen_string_literal: true

module Billing
  class SalesServeWebhookNotifier
    include UrlHelpers

    NOTIFICATION_SLACK_CHANNEL = "#sales-operations"

    def initialize(webhook)
      @webhook = webhook
    end

    attr_accessor :webhook

    # Internal: The Zuora subscription referenced in the webhook
    #
    # Returns Zuorest Subscription
    def subscription
      @_subscription ||= Zuorest::Model::Subscription.find(webhook.subscription_id)
    end

    # Internal: The account linked to the webhook
    #
    # Returns a Business or Organization (or nil)
    def webhook_account
      case
      when subscription[:DotcomEntAccountId__c].present?
        Business.find_by(id: subscription[:DotcomEntAccountId__c])
      when subscription[:DotcomOrgId__c].present?
        Organization.find_by(id: subscription[:DotcomOrgId__c])
      else
        nil
      end
    end

    # Internal: Identifier and type of account
    #
    # account - Organization or Business to format
    #
    # Returns String
    def formatted_account
      case webhook_account
      when Business
        "#{webhook_account.slug} (Enterprise Account)"
      when Organization
        "#{webhook_account.login} (Organization)"
      else
        ""
      end
    end

    # Internal: The stafftools link to the account
    #
    # account - Organization or Business to link to
    #
    # Returns String
    def account_stafftools_link
      return "" unless webhook_account

      url_options = { host: "admin.github.com", protocol: "https" }
      url = case webhook_account
      when Business
        stafftools_enterprise_url(webhook_account, **url_options)
      when Organization
        stafftools_user_url(webhook_account, **url_options)
      end
      "[#{formatted_account} stafftools](#{url})"
    end

    # Send notification to sales-operations slack channel
    def send_notification
      unless !!Billing::Kv.store.get("sales-ops-webhook.alert.#{webhook.id}").value!
        # create a message
        message = "Failed Zuora Webhook for #{account_stafftools_link} /n To resolve, please visit the Zuora Webhooks dashboard"
        GitHub::Chatterbox.client.say(NOTIFICATION_SLACK_CHANNEL, message)
        # Use Billing::Kv.store.set to mark a Slack message as having been sent
        Billing::Kv.store.set "sales-ops-webhook.alert.#{webhook.id}", GitHub::Billing.today.to_s,
          expires: 7.days.from_now
      end
    end
  end
end
