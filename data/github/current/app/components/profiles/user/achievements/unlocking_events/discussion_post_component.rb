# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class DiscussionPostComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :post, :unlocking_model

          def team
            post&.team
          end

          def org
            team&.organization
          end

          def render_accessible_model
            href = team_discussion_path(org.display_login, team.slug, post.number)
            content_tag(:a, post.title, class: "Link", href: href)
          end
        end
      end
    end
  end
end
