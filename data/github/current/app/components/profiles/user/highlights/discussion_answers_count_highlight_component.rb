# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Highlights
      class DiscussionAnswersCountHighlightComponent < ApplicationComponent
        def initialize(profile_layout_data:)
          @profile_layout_data = profile_layout_data
        end

        def render?
          !GitHub.achievements_enabled? && discussion_answered_count > 0
        end

        private

        attr_reader :profile_layout_data

        delegate :discussion_answered_count, to: :profile_layout_data
        delegate :social_count, to: :helpers
      end
    end
  end
end
