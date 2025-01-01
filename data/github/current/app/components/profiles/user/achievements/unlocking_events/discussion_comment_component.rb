# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class DiscussionCommentComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :comment, :unlocking_model

          def discussion
            comment&.discussion
          end

          def repo
            comment&.repository
          end

          def render_accessible_model
            # We can't use anchor: because discussion_path is redefined
            href = "#{discussion_path(discussion, repo)}##{comment.dom_id}"
            content_tag(:a, "#{repo.name_with_display_owner}##{discussion.number}", href: href)
          end
        end
      end
    end
  end
end
