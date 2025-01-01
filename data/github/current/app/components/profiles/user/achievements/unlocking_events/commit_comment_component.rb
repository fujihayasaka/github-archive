# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class CommitCommentComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :commit_comment, :unlocking_model

          def repo
            commit_comment&.repository
          end

          def render_accessible_model
            # This is consistent with the way the anchor is generated in the parial that renders the comment:
            # app/views/commit/_timeline_marker.html.erb
            href = commit_path(commit_comment.commit_id, repo) + "#commitcomment-#{commit_comment.id}"
            content_tag(:a, "#{repo.name_with_display_owner}##{commit_comment.abbreviated_oid}", href: href)
          end
        end
      end
    end
  end
end
