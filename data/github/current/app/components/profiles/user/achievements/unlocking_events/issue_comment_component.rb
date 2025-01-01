# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class IssueCommentComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :comment, :unlocking_model

          delegate :comment_dom_id, to: :helpers

          def issue
            comment&.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          def repo
            comment&.repository
          end

          def render_accessible_model
            href = issue_path(repo.owner_display_login, repo.name, issue.number, anchor: comment_dom_id(comment))
            content_tag(:a, "#{repo.name_with_display_owner}##{issue.number}", href: href)
          end
        end
      end
    end
  end
end
