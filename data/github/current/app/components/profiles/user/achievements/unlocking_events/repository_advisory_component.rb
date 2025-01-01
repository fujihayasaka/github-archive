# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class RepositoryAdvisoryComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :advisory, :unlocking_model

          def repo
            advisory&.repository
          end

          def render_accessible_model
            href = repository_advisory_path(repo.owner_display_login, repo.name, advisory.ghsa_id)
            content_tag(:a, advisory.ghsa_id, href: href)
          end
        end
      end
    end
  end
end
