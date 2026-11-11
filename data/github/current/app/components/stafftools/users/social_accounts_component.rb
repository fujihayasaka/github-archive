# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class SocialAccountsComponent < ApplicationComponent
      def initialize(user_profile:, nodeinfo_cache_values:)
        @user_profile = user_profile
        @nodeinfo_cache_values = nodeinfo_cache_values
      end

      private

      attr_reader :user_profile, :nodeinfo_cache_values
      delegate :social_account_icon, to: :helpers

      def render?
        user_profile.present?
      end

      memoize def social_accounts
        Array(user_profile.social_accounts)
      end

      def more_info(account)
        if account.needs_nodeinfo_recognition?
          nodeinfo_url = Addressable::URI.join(account.url, "/.well-known/nodeinfo").normalize.to_s
          nodeinfo_cached_value = nodeinfo_cache_values[account]

          link_to(nodeinfo_url, target: "_blank") do
            safe_join([
              "Nodeinfo: ",
              nodeinfo_cached_value || "(no cached value)",
              primer_octicon("link-external"),
            ])
          end
        end
      end
    end
  end
end
