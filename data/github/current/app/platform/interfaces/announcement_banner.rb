# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AnnouncementBanner
      include Platform::Interfaces::Base

      description "Represents an announcement banner."

      field :announcement, String, "The text of the announcement", null: true

      def announcement
        async_get_banner.then do |banner|
          banner&.message.presence
        end
      end

      field :announcement_expires_at, Platform::Scalars::DateTime, "The expiration date of the announcement, if any", null: true

      def announcement_expires_at
        async_get_banner.then do |banner|
          banner&.expires_at.presence
        end
      end

      field :announcement_user_dismissible, Boolean, "Whether the announcement can be dismissed by the user", null: true

      def announcement_user_dismissible
        async_get_banner.then do |banner|
          banner&.dismissible
        end
      end

      field :announcement_created_at, Platform::Scalars::DateTime, "The date the announcement was created", null: true

      def announcement_created_at
        async_get_banner.then do |banner|
          banner&.created_at
        end
      end

      field :is_announcement_dismissed, Boolean, "Whether the announcement has been dismissed by the viewer", visibility: :internal, null: true

      def is_announcement_dismissed
        async_get_banner.then do |banner|
          next nil if banner.nil?

          Platform::Loaders::BannerDismissalsByUser.load(banner.id, @context[:viewer].id).then do |dismissed|
            dismissed.present?
          end
        end
      end

      private

      def async_get_banner
        return Promise.new.fulfill(@banner) if defined?(@banner)

        banner = EnterpriseBanner.active.find_by(owner: @object)

        if @object.is_a?(Platform::Models::Enterprise)
          Promise.new.fulfill(assign_banner_if_member_of_business(banner, @object))
        else
          @object.async_business.then do |business|
            assign_banner_if_member_of_business(banner, business)
          end
        end
      end

      def assign_banner_if_member_of_business(banner, business)
        if banner && @context[:viewer] && EnterpriseBanner.user_in_business(@context[:viewer], business)
          @banner = banner
        else
          @banner = nil
        end

        @banner
      end
    end
  end
end
