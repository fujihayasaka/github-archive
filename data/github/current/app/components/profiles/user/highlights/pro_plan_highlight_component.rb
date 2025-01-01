# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Highlights
      class ProPlanHighlightComponent < ApplicationComponent
        include ViewComponent::InlineTemplate

        def initialize(profile_layout_data:)
          # noop
        end

        erb_template <<~'ERB'
          <li class="mt-2">
            <%= render "users/pro_badge" %>
          </li>
        ERB
      end
    end
  end
end
