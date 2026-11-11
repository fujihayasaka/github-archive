# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TeamDiscussionComment < Platform::Objects::Base
      model_name "DiscussionPostReply"
      description "A comment on a team discussion."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, comment)
        comment.async_organization.then do |org|
          permission.access_allowed?(
            :show_team_discussion_comment,
            resource: comment,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_discussion_post.then { |discussion| permission.typed_can_see?("TeamDiscussion", discussion) }
      end

      minimum_accepted_scopes ["read:discussion"]

      implements_node templates: [[:ottdc, :organization_id, :team_id, :team_discussion_id, :team_discussion_comment_id]], as: "TDC", ready_date: "2021-07-11" do |comment|
        comment.async_discussion_post.then do |post|
          post.async_team.then do |team|
            team.async_organization.then do |org|
              {
                prefix: :ottdc,
                organization_id: org.id,
                team_id: team.id,
                team_discussion_id: post.id,
                team_discussion_comment_id: comment.id
              }
            end
          end
        end
      end

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Reactable
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment

      url_fields description: "The HTTP URL for this comment", deprecated: Helpers::TeamDiscussion::DeprecationNotice do |comment|
        comment.async_discussion_post.then do |post|
          post.async_team.then do |team|
            team.async_organization.then do |org|
              template = Addressable::Template.new(
                "/orgs/{org}/teams/{team}/discussions/{post}/comments/{comment}")
              template.expand(
                org: org.display_login,
                team: team.slug,
                post: post.number,
                comment: comment.number)
            end
          end
        end
      end

      field :number, Integer, "Identifies the comment number.", null: false, deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :author_association, Enums::CommentAuthorAssociation, description: "Author's association with the comment's team.", null: false, deprecated: Helpers::TeamDiscussion::DeprecationNotice do
        # This association is defined by `Interfaces::Comment` in relation to a repository. A
        # `TeamDiscussionComment` is not associated with repository, but to rather with a team. Since
        # currently org members can create comments, we return `:member` by default.
      end

      def author_association
        :member
      end

      field :body_version, String, description: "The current version of the body content.", null: false, deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :discussion, TeamDiscussion, method: :async_discussion_post, description: "The discussion this comment is about.", null: false, deprecated: Helpers::TeamDiscussion::DeprecationNotice
    end
  end
end
