# typed: true
# frozen_string_literal: true

module Profiles
  module Achievements
    class BaseController < ::ApplicationController
      REPO_LIMIT = 3.freeze

      include ProfilesHelper
      include ControllerMethods

      before_action :require_achievements_to_be_enabled
      before_action :require_user
      before_action :ensure_not_organization
      before_action :ensure_not_mannequin
      before_action :ensure_profile_visible
      before_action :ensure_profile_setting_enabled

      javascript_bundle :profile
      stylesheet_bundle :profile

      private

      def require_achievements_to_be_enabled
        render_404 unless GitHub.achievements_enabled?
      end

      def require_user
        render_404 unless this_user
      end

      def ensure_not_organization
        render_404 if this_user.organization?
      end

      def ensure_not_mannequin
        render_404 if this_user.mannequin?
      end

      def ensure_profile_setting_enabled
        render_404 unless this_user.profile_settings.achievements_enabled?
      end

      memoize def this_user
        ::User.find_by_login(params[:user_id]) if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      end

      memoize def highest_tier_achievements
        this_user.highest_tier_achievements(viewer: current_user).
          select { |achievement| achievement.achievable.enabled?(current_user) }
      end

      memoize def achieved_tiers
        return [] unless achievable_slug && GitHub::UTF8.valid_unicode3?(achievable_slug)

        achievable = Achievable.with_slug(achievable_slug)
        return [] unless achievable&.enabled?(current_user)

        this_user.
          achievements_for(achievable, viewer: current_user).
          includes(:unlocking_model).
          order(tier: :asc).
          to_a
      end

      def require_achieved_tiers
        render_404 unless achieved_tiers.any?
      end

      def target_for_conditional_access
        return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
        this_user
      end

      memoize def achievable_slug
        params[:achievable_slug] || params[:achievement_slug]
      end
    end
  end
end
