# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateTeamDiscussion < Platform::Mutations::Base
      description "Creates a new team discussion."

      minimum_accepted_scopes ["write:discussion"]

      argument :team_id, ID, "The ID of the team to which the discussion belongs. This field is required.",
        required: false, loads: Objects::Team, deprecated: Helpers::TeamDiscussion::DeprecationNotice
      argument :title, String, "The title of the discussion. This field is required.", required: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice
      argument :body, String, "The content of the discussion. This field is required.", required: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice
      argument :private, Boolean, "If true, restricts the visibility of this discussion to team members and " \
        "organization owners. If false or not specified, allows any organization member to view this discussion.", required: false,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      field :team_discussion, Objects::TeamDiscussion, "The new discussion.", null: true,
        deprecated: Helpers::TeamDiscussion::DeprecationNotice

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, team:, **inputs)
        # Those 2 arguments are in fact _required_ but we need to mark them as _optional_ since we are deprecating
        # this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::TeamDiscussion.raise_missing_mutation_argument(:body, self) if inputs[:body].nil?
        Platform::Helpers::TeamDiscussion.raise_missing_mutation_argument(:title, self) if inputs[:title].nil?

        team.async_organization.then do |org|
          if org && org.feature_enabled?(:teams_cap_updates)
            permission.access_allowed?(
              :create_team_discussion,
              resource: team,
              team: team,
              organization: org,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true)
          else
            permission.access_allowed?(
              :create_team_discussion,
              resource: team,
              organization: org,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(team:, **inputs)
        if inputs[:private] && !(team.adminable_by?(context[:viewer]) ||
          Team.member_of?(team.id, context[:viewer].id))

          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} can't create a private discussion without being a member of " +
            "#{team.name_with_display_owner}.")
        end

        raise Errors::Validation.new("Title can't be blank") if inputs[:title]&.strip.blank?

        unless team.async_fgp_team_post_creatable?(context[:viewer]).sync
          raise Errors::Forbidden.new("Viewer not authorized to create post")
        end

        discussion = team.discussion_posts.build(
          title: inputs[:title],
          body: inputs[:body],
          private: inputs[:private] || false,
          user: context[:viewer])

        if discussion.save
          { team_discussion: discussion }
        else
          raise Errors::Validation.new(discussion.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
