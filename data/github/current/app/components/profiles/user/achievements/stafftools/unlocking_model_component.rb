# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module Stafftools
        class UnlockingModelComponent < ApplicationComponent
          def initialize(user:, achievement:, visible_models: [])
            @achievement = achievement
            @user = user
            @visible_models = visible_models
          end

          private

          attr_reader :achievement, :user, :visible_models

          delegate :current_repository, to: :helpers

          def page_title
            "#{user} - Edit Achievement"
          end

          def tier_description
            Achievable::SubstitutedText.new(
              achievement.unlocking_explanation_template,
              achievement: achievement,
              current_user: current_user,
              visible_models: visible_models,
              view_context: self,
            ).to_s
          end

          def form_path
            if achievement.persisted?
              stafftools_user_achievement_path(user, achievement)
            else
              stafftools_user_achievements_path(user, achievement)
            end
          end
        end
      end
    end
  end
end
