# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Highlights
      class DeveloperProgramHighlightComponent < ApplicationComponent
        def initialize(profile_layout_data:)
          @profile_layout_data = profile_layout_data
        end

        private

        attr_reader :profile_layout_data

        delegate :user_is_viewer?, to: :profile_layout_data

        def developer_program_badge_link_href
          if user_is_viewer?
            settings_user_profile_path(anchor: "github-developer-program")
          else
            "#{GitHub.help_url}/developers/overview/github-developer-program"
          end
        end
      end
    end
  end
end
