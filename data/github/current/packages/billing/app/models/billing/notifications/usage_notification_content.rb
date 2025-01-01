# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class UsageNotificationContent
      attr_reader :text, :threshold, :within_entitlements, :scope, :mail_subject, :mail_product_title, :mail_icon, :show_progress_bar, :progress_bar_title, :progress_bar_details_text, :usage_reset_date_text, :slack_notification_message, :disabled_services, :meter_available, :action_text, :filtered_by_tags, :product_tags

      def initialize(text:, threshold:, within_entitlements:, scope:, mail_subject:, mail_product_title:, mail_icon:, show_progress_bar:, progress_bar_title:, progress_bar_details_text:, usage_reset_date_text:, slack_notification_message:, disabled_services:, meter_available:, action_text:, filtered_by_tags: nil, product_tags: [])
        @text = text
        @threshold = threshold
        @within_entitlements = within_entitlements
        @scope = scope
        @mail_subject = mail_subject
        @mail_product_title = mail_product_title
        @mail_icon = mail_icon
        @show_progress_bar = show_progress_bar
        @progress_bar_title = progress_bar_title
        @progress_bar_details_text = progress_bar_details_text
        @usage_reset_date_text = usage_reset_date_text
        @slack_notification_message = slack_notification_message
        @disabled_services = disabled_services
        @filtered_by_tags = filtered_by_tags
        @meter_available = meter_available
        @action_text = action_text
        @product_tags = product_tags
      end

      def within_entitlements?
        !!@within_entitlements
      end

      def variant
        threshold >= Billing::Notifications::ERROR_THRESHOLD ? :danger : :warning
      end

      def threshold_text
        Billing::Notifications::THRESHOLDS[threshold]
      end
    end
  end
end
