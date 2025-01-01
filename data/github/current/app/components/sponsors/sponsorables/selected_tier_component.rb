# typed: true
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class SelectedTierComponent < ApplicationComponent
      # sponsorable - a User or Organization
      # sponsor - a User or Organization
      # tier - a SponsorsTier
      # sponsorship - the Sponsorship from `sponsor` to `sponsorable`, if one exists
      # preview - Boolean indicating whether the sponsorable is previewing their own sponsorship checkout page
      # sponsorable_metadata - optional Hash of user-given metadata for the sponsorship, data the sponsorable may
      #                        have specified
      # parent_tier - optional SponsorsTier that's the closest lesser-value tier of the same frequency as `tier`;
      #               only applicable if `tier` is a custom tier
      def initialize(sponsorable:, sponsor:, tier:, sponsorship: nil, preview: false, sponsorable_metadata: nil, parent_tier: nil)
        @sponsorable = sponsorable
        @sponsor = sponsor
        @tier = tier
        @sponsorship = sponsorship
        @preview = preview
        @sponsorable_metadata = sponsorable_metadata || {}
        @parent_tier = parent_tier
      end

      private

      attr_reader :parent_tier

      def render?
        @tier&.name.present?
      end

      def show_repo_access_message?
        @tier.grants_repository_access_to?(@sponsor)
      end

      memoize def tier_is_sponsorship_tier?
        current_tier == @tier
      end

      def edit_tiers_path
        params = @sponsorable_metadata.merge(
          preview: @preview,
          sponsor: @sponsor.display_login,
        )

        if @tier.new_record? && @tier.custom?
          params[:amount] = @tier.monthly_price_in_dollars.to_i
        end
        params[:frequency] = "one-time" if @tier.one_time?
        edit_sponsorable_sponsorships_path(@sponsorable, params)
      end

      memoize def repository
        @tier.repository_for_sponsor(@sponsor)
      end

      def current_tier
        return unless @sponsorship

        if pending_downgrade?
          pending_tier_change.subscribable
        else
          @sponsorship.tier
        end
      end

      def from_org?
        if @sponsorship
          @sponsorship.from_organization?
        else
          @sponsor&.organization?
        end
      end

      def chosen_by
        if custom_tier_creator == current_user
          "you"
        else
          "@#{custom_tier_creator}"
        end
      end

      memoize def custom_tier_creator
        if @sponsorship && @sponsorship.custom_tier?
          @sponsorship.tier_creator
        elsif @tier&.custom?
          @tier.creator
        end
      end

      def can_change_tier?
        # Not yet sponsoring, can swap which tier they're looking at
        return true unless @sponsorship

        # Only an unlocked sponsorship can have its tier changed; if it's locked,
        # that means we need to keep the tier the same while Zuora processes
        # a one-time payment
        return false if @sponsorship.locked?

        !pending_tier_change?
      end

      def pending_downgrade?
        return false unless pending_tier_change?
        !pending_tier_change.cancellation?
      end

      def pending_tier_change?
        pending_tier_change.present?
      end

      memoize def pending_tier_change
        @sponsorship.pending_subscription_item_change
      end

      def sponsorship_supports_tier_change?
        @tier.recurring?
      end

      def rewards_text
        if @tier.custom?
          return "Custom amount." unless default_reward_text

          "Custom amount. " + default_reward_text
        else
          return @tier.description_html unless show_public_badge_reward_text?

          badge_text = "<p>" + public_badge_reward_text + "</p>"
          badge_text += "<p>You'll also receive rewards listed in the <strong>#{@tier.name}</strong> tier:</p>"
          ActiveSupport::SafeBuffer.new(badge_text) + @tier.description_html
        end
      end

      def default_reward_text
        if show_public_badge_reward_text?
          public_badge_reward_text
        elsif parent_tier.nil?
          no_reward_text
        end
      end

      memoize def show_public_badge_reward_text?
        achievement = @sponsor.achievements_for(Achievable::PublicSponsor)

        return true unless achievement

        achievement.empty?
      end

      def public_badge_reward_text
        "A Public Sponsor achievement will be added to your profile."
      end

      def no_reward_text
        "There are no rewards associated with this sponsorship."
      end
    end
  end
end
