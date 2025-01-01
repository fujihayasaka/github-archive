# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class DisabledCtaComponent < ApplicationComponent
        def initialize(
          achievements_enabled:,
          has_unseen_private_achievement:,
          has_unseen_public_achievement:,
          private_contribution_count_enabled:,
          user_is_viewer:
        )
          @achievements_enabled = achievements_enabled
          @has_unseen_private_achievement = has_unseen_private_achievement
          @has_unseen_public_achievement = has_unseen_public_achievement
          @private_contribution_count_enabled = private_contribution_count_enabled
          @user_is_viewer = user_is_viewer
        end

        def render?
          eligible_for_notice?
        end

        private

        def eligible_for_notice?
          return false unless user_is_viewer?
          return false unless GitHub.achievements_enabled?
          return false if current_user.dismissed_notice?(:disabled_achievements_cta)

          appropriate_flash_message_to_show?
        end

        def user_is_viewer?
          @user_is_viewer
        end

        def appropriate_flash_message_to_show?
          has_unseen_achievements? && notice_message.present?
        end

        def achievements_enabled?
          @achievements_enabled
        end

        def private_contribution_count_enabled?
          @private_contribution_count_enabled
        end

        def private_contributions_hidden?
          has_unseen_private_achievements? && !private_contribution_count_enabled?
        end

        def dismissal_path
          dismiss_notice_path(:disabled_achievements_cta)
        end

        def notice_message
          if achievements_enabled?
            if private_contributions_hidden?
              message_with(:ach_enabled_private_contributions_hidden)
            end
          else
            if private_contributions_hidden?
              message_with(:ach_disabled_private_contributions_hidden)
            else
              message_with(:ach_disabled)
            end
          end
        end

        def message_with(variant)
          message_variant = message_text_variants[variant]

          safe_join([
            message_variant[:text],
            " ",
            link_to("settings", settings_user_profile_path(anchor: message_variant[:anchor])),
            ".",
          ])
        end

        def has_unseen_achievements?
          @has_unseen_public_achievement || @has_unseen_private_achievement
        end

        def has_unseen_private_achievements?
          @has_unseen_private_achievement
        end

        memoize def message_text_variants
          {
            ach_enabled_private_contributions_hidden: {
              text: I18n.t("achievements.disabled_cta.ach_enabled_private_contributions_hidden"),
              anchor: "contributions-activity-heading",
            },
            ach_disabled_private_contributions_hidden: {
              text: I18n.t("achievements.disabled_cta.ach_disabled_private_contributions_hidden"),
              anchor: "profile-settings-heading",
            },
            ach_disabled: {
              text: I18n.t("achievements.disabled_cta.ach_disabled"),
              anchor: "profile-settings-heading",
            },
          }
        end
      end
    end
  end
end
