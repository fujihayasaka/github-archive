# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class SponsorshipComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :sponsorship, :unlocking_model

          def render_accessible_model
            sponsorable = sponsorship.sponsorable

            content_tag(
              :a,
              "@#{sponsorable}",
              href: user_path(sponsorable),
              class: "user-mention Link",
              **helpers.hovercard_data_attributes_for_user(sponsorable),
            )
          end
        end
      end
    end
  end
end
