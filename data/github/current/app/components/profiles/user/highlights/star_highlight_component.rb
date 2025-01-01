# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Highlights
      class StarHighlightComponent < ApplicationComponent
        def initialize(profile_layout_data:)
          @profile_layout_data = profile_layout_data
        end

        private

        attr_reader :profile_layout_data

        delegate :login_name, to: :profile_layout_data

        def stars_program_href
          "#{GitHub.stars_program_url}/profiles/#{login_name}/"
        end
      end
    end
  end
end
