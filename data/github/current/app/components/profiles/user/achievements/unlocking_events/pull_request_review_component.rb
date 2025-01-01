# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class PullRequestReviewComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :review, :unlocking_model

          delegate :comment_dom_id, to: :helpers

          def pr
            review&.pull_request
          end

          def repo
            review&.repository
          end

          def render_accessible_model
            href = show_pull_request_path(repo.owner_display_login, repo.name, pr.number, anchor: comment_dom_id(review))
            content_tag(:a, "#{repo.name_with_display_owner}##{pr.number}", class: "Link", href: href)
          end
        end
      end
    end
  end
end
