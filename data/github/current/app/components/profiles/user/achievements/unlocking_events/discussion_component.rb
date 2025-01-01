# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class DiscussionComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :discussion, :unlocking_model

          def repo
            discussion&.repository
          end

          def render_accessible_model
            content_tag(:a, "#{repo.name_with_display_owner}##{discussion.number}", href: discussion_path(discussion, repo))
          end
        end
      end
    end
  end
end
