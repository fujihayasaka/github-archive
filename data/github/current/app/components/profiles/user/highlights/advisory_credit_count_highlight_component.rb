# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Highlights
      class AdvisoryCreditCountHighlightComponent < ApplicationComponent
        def initialize(profile_layout_data:)
          @profile_layout_data = profile_layout_data
        end

        def render?
          global_advisory_credit_count > 0
        end

        private

        attr_reader :profile_layout_data

        delegate :global_advisory_credit_count, :login_name, to: :profile_layout_data
        delegate :social_count, to: :helpers
      end
    end
  end
end
