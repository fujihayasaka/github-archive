# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GitActor < Platform::Objects::Base
      description "Represents an actor in a Git commit (ie. an author or committer)."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :name, String, method: :display_name, description: "The name in the Git commit.", null: true

      field :email, String, method: :display_email, description: "The email in the Git commit.", null: true

      field :avatar_url, Scalars::URI, description: "A URL pointing to the author's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        if GitHub.private_mode_enabled? && !GitHub.multi_tenant_enterprise? && Apps::Privileged.capable?(:enterprise_avatar_display, app: context[:oauth_app])
          @object.async_visible_actor(@context[:viewer]).then do |user|
            if user
              "#{GitHub.api_url}/enterprise/avatars#{user.primary_avatar_path}?s=#{arguments[:size]}"
            else
              template = Addressable::Template.new("/enterprise/avatars/u/e?email={email}?s={size}")
              GitHub.api_url + (template.expand email: @object.email, size: arguments[:size])
            end
          end
        else
          @object.async_visible_avatar_url(@context[:viewer], size: arguments[:size])
        end
      end

      # TODO: define_url_field should be used here but doesn't yet support nullable values.
      #   When that method is updated, this definition should be migrated which will
      #   automatically add the corresponding definition for commitsUrl.
      field :commits_resource_path, Scalars::URI, visibility: :internal, method: :async_commits_path_uri, description: "The HTTP URL to the actor's list of commits for the associated repository.", null: true

      field :user, Objects::User, description: "The GitHub user corresponding to the email field. Null if no such user exists.", null: true

      def user
        return nil if CommitHelper.via_github?(committer_name: @object.name, committer_email: @object.email)
        @object.async_visible_user(@context[:viewer])
      end

      field :actor, Interfaces::Actor, visibility: :under_development, description: "The actor corresponding to the email field. Null if no such actor exists.", null: true

      def actor
        return nil if CommitHelper.via_github?(committer_name: @object.name, committer_email: @object.email)
        @object.async_visible_actor(@context[:viewer])
      end

      field :date, Scalars::GitTimestamp, "The timestamp of the Git action (authoring or committing).", method: :time, null: true
    end
  end
end
