# typed: true
# frozen_string_literal: true

module Profiles
  module Achievements
    class VisibilitiesController < BaseController
      before_action :require_achievement_owner
      before_action :ensure_valid_achievement
      after_action :instrument_metadata_recalculation

      def create
        achievements.update_all(hidden: false)
        instrument_metadata_recalculation

        redirect_to(
          user_achievement_url(current_user, achievable_slug),
          notice: "The #{achievement_representative.display_name} achievement will now be "\
          "shown in your profile."
        )
      end

      def destroy
        achievements.update_all(hidden: true)
        instrument_metadata_recalculation

        redirect_to(
          user_achievement_url(current_user, achievable_slug),
          notice: "The #{achievement_representative.display_name} achievement will now be "\
            "hidden from your profile."
        )
      end

      private

      def require_achievement_owner
        render_404 unless this_user.id == current_user.id
      end

      def ensure_valid_achievement
        render_404 unless achievements.present?
      end

      memoize def achievements
        this_user.achievements.where(achievable_slug: achievable_slug)
      end

      def instrument_metadata_recalculation
        after_response do
          GlobalInstrumenter.instrument(
            "user_metadata.recalculation.trigger",
            {
              actor_id: achievement_representative.user_id,
              target_user_id: achievement_representative.user_id,
              target_stream_processor: :ALL,
            },
          )
        end
      end

      def achievement_representative
        achievements.first
      end
    end
  end
end
