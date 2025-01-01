# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class AchievementsComponent < ApplicationComponent
      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      def render?
        GitHub.achievements_enabled? &&
          achievements_enabled? &&
          achievables_and_tiers.any?
      end

      def call
        desktop_achievements_section = safe_join(
          [
            achievements_heading,
            content_tag(:div, displayable_achievements(type: :desktop), class: "d-flex flex-wrap"),
          ],
        )

        mobile_achievements_section = safe_join(
          [
            achievements_heading,
            content_tag(:div, displayable_achievements(type: :mobile), class: "d-flex flex-wrap"),
          ],
        )

        safe_join(
          [
            content_tag(
              :div,
              desktop_achievements_section,
              class: "border-top color-border-muted pt-3 mt-3 d-none d-md-block",
            ),
            content_tag(
              :div,
              mobile_achievements_section,
              class: "border-top color-border-muted pt-3 mt-3 d-md-none d-block",
            ),
          ],
        )
      end

      private

      attr_reader :profile_layout_data

      delegate(
        :achievements_enabled?,
        :login_name,
        :user_is_viewer?,
        to: :profile_layout_data,
      )

      def displayable_achievements(type:)
        achievements = achievables_and_tiers.map do |achievable, tier|
          href = user_path(profile_layout_data.profile_user, params: {
            tab: :achievements,
            achievement: achievable.slug,
          })
          content_tag(:a, href:, class: "position-relative") do
            safe_join([
              render(Primer::Alpha::Image.new(
                alt: "Achievement: #{achievable.display_name}",
                classes: "achievement-badge-sidebar",
                data: hovercard_data_attributes_for_achievement(
                  login: profile_layout_data.login_name,
                  slug: achievable.slug,
                ),
                src: achievable.badge_asset_path(skin_tone_block: skin_tone_block),
                test_selector: "achievement-#{achievable.slug}-badge",
                width: 64,
              )),
              render(Profiles::User::Achievements::TierLabelComponent.new(
                achievable: achievable,
                tier: tier,
                px: 2, py: 0,
                mb: 1,
                position: :absolute,
                right: false, bottom: false,
              )),
            ])
          end
        end

        safe_join(achievements)
      end

      def achievements_heading
        url = user_path(profile_layout_data.profile_user, params: { tab: :achievements })

        content_tag(:h2, class: "h4 mb-2") do
          content_tag(:a, "Achievements", href: url, class: "Link--primary mb-2")
        end
      end

      memoize def achievables_and_tiers
        profile_layout_data.achievables_and_tiers.select { |achievable, _tier| achievable.enabled?(current_user) }
      end

      def skin_tone_block
        profile_layout_data.method(:achievement_skin_tone)
      end
    end
  end
end
