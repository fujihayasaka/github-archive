# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class BaseComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
        private

        def description
          render_text_with_substitutions(achievement.description_template)
        end

        def render_text_with_substitutions(text)
          Achievable::SubstitutedText.new(
            text,
            achievement: achievement,
            current_user: current_user,
            visible_models: visible_models,
            view_context: self,
          ).to_s
        end

        # Accessors that subclasses need to override to use #render_text_with_substitutions

        def achievement
          raise "#{self.class.name} has not overridden #achievement"
        end

        def visible_models
          []
        end

        delegate :hovercard_data_attributes_for_user, to: :helpers
      end
    end
  end
end
