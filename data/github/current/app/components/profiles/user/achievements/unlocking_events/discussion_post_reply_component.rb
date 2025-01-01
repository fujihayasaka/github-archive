# typed: false
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      module UnlockingEvents
        class DiscussionPostReplyComponent < ::Profiles::User::Achievements::UnlockingEvents::BaseComponent
          private

          alias_method :reply, :unlocking_model

          def post
            reply&.discussion_post
          end

          def team
            post&.team
          end

          def org
            team&.organization
          end

          def render_accessible_model
            anchor = team_discussion_comment_dom_id(
              discussion_number: post.number,
              comment_number: reply.number,
            )
            href = team_discussion_path(
              org: org.display_login,
              team_slug: team.slug,
              number: post.number,
              from_comment: reply.number,
              anchor: anchor,
            )
            content_tag(:a, post.title, href: href)
          end

          # Internal: Returns the value that should be used for the `id` attribute of
          # the top-level DOM element used to display a TeamDiscussionComment or
          # OrganizationDiscussionComment GraphQL object.
          #
          # Returns: a String.
          def team_discussion_comment_dom_id(discussion_number:, comment_number:)
            "discussion-#{discussion_number}-comment-#{comment_number}"
          end
        end
      end
    end
  end
end
