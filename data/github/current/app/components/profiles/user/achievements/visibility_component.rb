# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class VisibilityComponent < Profiles::User::Achievements::BaseComponent
        # achievement - the achievement to update visibility for
        def initialize(achievement:)
          @achievement = achievement
          @state = achievement.hidden? ? HiddenState.new : VisibleState.new
        end

        private

        delegate(
          :current_hidden_status_icon,
          :current_hidden_status_text,
          :current_hidden_status_form_method,
          to: :@state,
          private: true,
        )

        attr_reader :achievement

        def render?
          return false unless GitHub.achievements_enabled?
          return false unless user_or_global_feature_enabled?(:achievements_hiding_menu)

          achievement.user.id == current_user&.id
        end

        class HiddenState
          def current_hidden_status_icon ; :"eye-closed" ; end
          def current_hidden_status_text ; "Show on profile" ; end
          def current_hidden_status_form_method ; :post ; end
        end

        class VisibleState
          def current_hidden_status_icon ; :eye ; end
          def current_hidden_status_text ; "Hide from profile" ; end
          def current_hidden_status_form_method ; :delete ; end
        end
      end
    end
  end
end
