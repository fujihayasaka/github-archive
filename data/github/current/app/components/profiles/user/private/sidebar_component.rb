# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class SidebarComponent < BaseSidebarComponent
        delegate(
          :follow_button,
          to: :helpers,
        )

        delegate(
          :show_follow_button?,
          to: :profile_layout_data,
        )
      end
    end
  end
end
