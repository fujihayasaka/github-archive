# typed: true
# frozen_string_literal: true

module Marketplace
  module Listings
    class DelistWarningComponent < ApplicationComponent
      WARNING_ALERT = "Unexpected bad things will happen if you don’t read this!"
      attr_reader :listing, :stage

      def initialize(listing:, stage:)
        @listing = listing
        @stage = stage
      end

      def warning_message
        if stage == 2
          detailed_warning_message
        end
      end

      def main_warning_message
        safe_join([
          content_tag(:div, class: "flash mt-3 flash-warn") do
            safe_join([primer_octicon(:alert), WARNING_ALERT])
          end
        ])
      end

      def build_display_message(message)
        render(Primer::Beta::TimelineItem.new(
          p: 0,
          condensed: true,
          classes: "repository-delete-warning",
        )) do |component|
          component.with_badge(bg: :transparent, color: :subtle, icon: :"dot-fill")
          component.with_body.with_content(message)
        end
      end

      def detailed_warning_message
        safe_join([
          tag.hr,
          main_warning_message,
          content_tag(:div, class: "mt-2") do
            safe_join([
              no_customer_message,
              subscription_cancellation_message,
              subscriber_email_message,
              app_deletion_message,
              relist_app_message
            ].compact)
          end,
          tag.br,
        ])
      end

      def no_customer_message
        build_display_message(
          safe_join([
            "The listing will no longer be available for installation by new customers."
          ]),
        )
      end

      def subscription_cancellation_message
        build_display_message(
          safe_join([
            "Subscriptions will be canceled at the end of the current billing cycle."
          ]),
        )
      end

      def subscriber_email_message
        build_display_message(
          safe_join([
            "Subscribers will be notified via email about the delisting"
          ]),
        )
      end

      def app_deletion_message
        build_display_message(
          safe_join([
            "You will be able to delete the app after the billing cycle."
          ]),
        )
      end

      def relist_app_message
        build_display_message(
          safe_join([
            "Please note that this action cannot be undone. You will have to submit your app for us to review if you wish to undo the action.
            More information can be found in",
            link_to("our developer documentation", GitHub.developer_help_url),
          ]),
        )
      end
    end
  end
end
