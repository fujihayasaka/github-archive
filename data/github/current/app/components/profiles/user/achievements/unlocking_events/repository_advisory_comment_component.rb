# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class RepositoryAdvisoryCommentComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :comment, :unlocking_model

          def advisory
            comment&.repository_advisory
          end

          def repo
            advisory&.repository
          end

          def render_accessible_model
            # Anchor is constructed directly to be consistent with the way it's built in the partial that renders it:
            # app/views/repos/advisories/_timeline.html.erb
            href = repository_advisory_path(repo.owner_display_login, repo.name, advisory.ghsa_id,
              anchor: "advisory-comment-#{comment.id}")
            content_tag(:a, "#{advisory.ghsa_id}", href: href)
          end
        end
      end
    end
  end
end
