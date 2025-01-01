# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class IssueComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :issue, :unlocking_model

          def repo
            issue&.repository
          end

          def render_accessible_model
            href = issue_path(repo.owner_display_login, repo.name, issue.number)
            content_tag(:a, "#{repo.name_with_display_owner}##{issue.number}", href: href)
          end
        end
      end
    end
  end
end
