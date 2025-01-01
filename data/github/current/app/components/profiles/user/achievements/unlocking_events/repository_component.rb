# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class RepositoryComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :repo, :unlocking_model

          def render_accessible_model
            content_tag(:a, repo.name_with_display_owner, href: repository_path(repo))
          end
        end
      end
    end
  end
end
