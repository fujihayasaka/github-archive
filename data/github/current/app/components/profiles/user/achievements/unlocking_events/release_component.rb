# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class ReleaseComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :release, :unlocking_model

          def repo
            release&.repository
          end

          def render_accessible_model
            href = show_release_path(repo.owner_display_login, repo.name, release.tag_name)
            content_tag(:a, "#{repo.name_with_display_owner} #{release.name}", class: "Link", href:)
          end
        end
      end
    end
  end
end
