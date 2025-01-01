# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class TeamDiscussion < Platform::Objects::Base
      model_name "DiscussionPost"
      description "A team discussion."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, discussion)
        discussion.async_organization.then do |org|
          permission.access_allowed?(
            :show_team_discussion,
            resource: discussion,
            organization: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:discussion"]

      implements_node templates: [[:ottd, :organization_id, :team_id, :team_discussion_id]], as: "TD", ready_date: "2021-07-11" do |team_discussion|
        team_discussion.async_team.then do |team|
          team.async_organization.then do |org|
            {
              prefix: :ottd,
              organization_id: org.id,
              team_id: team.id,
              team_discussion_id: team_discussion.id
            }
          end
        end
      end

      implements Interfaces::Comment
      implements Interfaces::Deletable
      implements Interfaces::Reactable
      implements Interfaces::Subscribable
      implements Interfaces::UniformResourceLocatable
      implements Interfaces::Updatable
      implements Interfaces::UpdatableComment

      url_fields(
        description: "The HTTP URL for this discussion",
        deprecated: Helpers::TeamDiscussion::DeprecationNotice,
      ) do |post|
        post.async_team.then do |team|
          team.async_organization.then do |org|
            template = Addressable::Template.new("/orgs/{org}/teams/{team}/discussions/{post}")
            template.expand org: org.display_login, team: team.slug, post: post.number
          end
        end
      end

      field :number, Integer, "Identifies the discussion within its team.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice
      field :is_pinned, Boolean, "Whether or not the discussion is pinned.", null: false, method: :pinned?,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice
      field :is_private, Boolean, "Whether or not the discussion is only visible to team members and organization owners.",
        null: false, method: :private?, deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :author_association, Enums::CommentAuthorAssociation,
        description: "Author's association with the discussion's team.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      def author_association
        # This association is defined by `Interfaces::Comment` and is related
        # to a repository. A `DiscussionPost` is not associated to any repository,
        # but to a team. As currently only team members can created posts,
        # we return `:member` by default.
        :member
      end

      field :title, String, description: "The title of the discussion", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      def title
        @object.title || GitHub::HTMLSafeString::EMPTY
      end

      field :body_version, String, description: "Identifies the discussion body hash.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      url_fields(
        prefix: "comments",
        description: "The HTTP URL for discussion comments",
        deprecated: Helpers::TeamDiscussion::DeprecationNotice,
      ) do |post|
        post.async_team.then do |team|
          team.async_organization.then do |org|
            template = Addressable::Template.new("/orgs/{org}/teams/{team}/discussions/{post}/comments")
            template.expand org: org.display_login, team: team.slug, post: post.number
          end
        end
      end

      field(:comments, Connections.define(Objects::TeamDiscussionComment),
        numeric_pagination_enabled: true,
        description: "A list of comments on this discussion.",
        null: false,
        connection: true,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice,
      ) do
        argument :order_by, Inputs::TeamDiscussionCommentOrder, "Order for connection", required: false
        argument :from_comment, Integer, "When provided, filters the connection such that results begin with the comment with this number.", required: false
      end

      def comments(**arguments)
        ordering = arguments[:order_by] || { field: "number", direction: "ASC" }

        scope = @object
          .replies
          .order("discussion_post_replies.#{ordering[:field]} #{ordering[:direction]}")

        if ordering[:field] == "number" && (number = arguments[:from_comment])
          scope = scope.where(
            "discussion_post_replies.number #{ordering[:direction] == "ASC" ? ">=" : "<="} ?",
            number)
        end

        scope.scoped
      end

      field :websocket, String, visibility: :internal,
        description: "The websocket channel ID for discussions live updates.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      def websocket
        GitHub::WebSocket::Channels.discussion_post(@object)
      end

      field :team, Objects::Team, method: :async_team, description: "The team that defines the context of this discussion.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :viewer_can_pin, Boolean, description: "Whether or not the current viewer can pin this discussion.", null: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      def viewer_can_pin
        @object.async_viewer_can_pin?(@context[:viewer])
      end

      def self.load_from_params(params)
        Loaders::ActiveRecord.load(::Organization, params[:org], column: :login).then do |org|
          Loaders::TeamBySlug.load(org, params[:team_slug]).then do |team|
            Loaders::TeamDiscussionByNumber.load(team.id, params[:number].to_i)
          end
        end
      end
    end
  end
end
