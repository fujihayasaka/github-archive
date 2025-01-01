# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StatusContext < Platform::Objects::Base
      model_name "Status"
      description "Represents an individual commit status context"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, status_context)
        permission.async_repo_and_org_owner(status_context).then do |repo, org|
          permission.access_allowed?(:read_status, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_creator.then do |creator|
          if creator && creator.hide_from_user?(permission.viewer)
            false
          else
            permission.belongs_to_repository(object)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::RequirableByPullRequest

      implements_node templates: [[:rsc, :repo_id, :status_context_id]], as: "SC", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |status_context|
        status_context.async_repository.then do |repository|
          {
            prefix: :rsc,
            repo_id: repository.id,
            status_context_id: status_context.id
          }
        end
      end

      field :commit, Objects::Commit, description: "This commit this status context is attached to.", null: true

      def commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.commit_oid, expected_type: :commit)
        end
      end

      field :state, Enums::StatusState, "The state of this status context.", null: false
      field :context, String, "The name of this status context.", resolver_method: :status_context, null: false
      # This field should get the _object's_ context, not the GraphQL query context.
      def status_context
        @object.context
      end

      field :description, String, "The description for this status context.", null: true

      field :target_url, Scalars::URI, "The URL for this status context.", null: true

      field :creator, description: "The actor who created this status context.", resolver: Resolvers::ActorCreator

      field :avatar_url, Scalars::URI, description: "The avatar of the OAuth application or the user that created the status", null: true do
        argument :size, Integer, "The size of the resulting square image.", default_value: 40, required: false
      end

      def avatar_url(**arguments)
        creator_avatar_url = @object.creator&.primary_avatar_url(arguments[:size])

        if @object.oauth_application_id
          Loaders::ActiveRecord.load(::OauthApplication, @object.oauth_application_id).then do |oauth_app|
            next creator_avatar_url unless oauth_app

            Loaders::ActiveRecordAssociation.load(oauth_app, :user).then do
              oauth_app.async_preferred_avatar_url(size: arguments[:size])
            end
          end
        else
          creator_avatar_url
        end
      end

      field :application, Platform::Objects::OauthApplication, method: :async_oauth_application, description: "The application that created this status context, if any.", null: true

      created_at_field
    end
  end
end
