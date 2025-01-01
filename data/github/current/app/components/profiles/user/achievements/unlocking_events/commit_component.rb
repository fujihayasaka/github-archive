# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class CommitComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :commit, :unlocking_model

          def repo
            commit&.repository
          end

          alias_method :authorizing_model, :repo

          def render_accessible_model
            content_tag(:a, "#{repo.name_with_display_owner}##{commit.abbreviated_oid}", href: commit_path(commit, repo))
          end
        end
      end
    end
  end
end
