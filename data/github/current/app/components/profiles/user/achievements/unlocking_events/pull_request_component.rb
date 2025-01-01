# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class PullRequestComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :pr, :unlocking_model

          def repo
            pr&.repository
          end

          def render_accessible_model
            href = show_pull_request_path(repo.owner_display_login, repo.name, pr.number)
            content_tag(:a, "#{repo.name_with_display_owner}##{pr.number}", class: "Link", href: href)
          end
        end
      end
    end
  end
end
