# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PublicKey < Platform::Objects::Base

      description "A user's public key."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, key)
        # PublicKey has a validation `user_or_repository_assigned` which says that it may have _either_ of these two:
        # - key.repository: a Deploy key
        # - key.user: A user's key
        self.check_permissions(permission, key)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, public_key)
        self.check_permissions(permission, public_key)
      end

      implements_node templates: [
        [:uk, :user_id, :id],
        #    These two are from a previous format which included the repo owner.
        # vv They're unused but should stay here for compatibility.
        [:urrk, :user_id, :repository_id, :id],
        [:orrk, :organization_id, :repository_id, :id],
        [:rk, :repository_id, :id]
      ], as: "PK", ready_date: "2021-05-15" do |key|
        key.async_repository.then do |repository|
          if repository.nil?
            {
              prefix: :uk,
              user_id: key.user_id,
              id: key.id
            }
          else
            {
              prefix: :rk,
              repository_id: key.repository_id,
              id: key.id,
            }
          end
        end
      end

      scopeless_tokens_as_minimum

      created_at_field  description: "Identifies the date and time when the key was created. Keys created before March 5th, 2014 have inaccurate values. Values will be null for keys not owned by the user.", null: true, minimum_accepted_scopes: ["read:public_key"]

      def created_at
        async_viewer_can_read_sensitive_fields.then do |can_read_fields|
          can_read_fields ? @object.created_at : nil
        end
      end

      updated_at_field  description: "Identifies the date and time when the key was updated. Keys created before March 5th, 2014 may have inaccurate values. Values will be null for keys not owned by the user.", null: true, minimum_accepted_scopes: ["read:public_key"]

      def updated_at
        async_viewer_can_read_sensitive_fields.then do |can_read_fields|
          can_read_fields ? @object.updated_at : nil
        end
      end

      field :fingerprint, String, description: "The fingerprint for this PublicKey.", null: false

      field :is_read_only, Boolean, description: "Whether this PublicKey is read-only or not. Values will be null for keys not owned by the user.", null: true, minimum_accepted_scopes: ["read:public_key"]

      def is_read_only
        async_viewer_can_read_sensitive_fields.then do |can_read_fields|
          can_read_fields ? @object.read_only? : nil
        end
      end

      field :accessed_at, Scalars::DateTime, description: "The last time this authorization was used to perform an action. Values will be null for keys not owned by the user.", null: true, minimum_accepted_scopes: ["read:public_key"]

      def accessed_at
        async_viewer_can_read_sensitive_fields.then do |can_read_fields|
          can_read_fields ? @object.accessed_at : nil
        end
      end

      field :key, String, "The public key string.", null: false

      def self.check_permissions(permission, key)
        async_user_and_repository(key).then do |user, repository|
          if repository
            permission.async_owner_if_org(repository).then do |org|
              permission.access_allowed? :list_repo_keys, \
                repo: repository,
                current_org: org,
                resource: repository,
                allow_integrations: true,
                allow_user_via_granular_actor: true
            end
          elsif user
            public_resource = Platform::PublicResource.new(resource: user)
            permission.access_allowed? :read_user_public, \
              resource: public_resource,
              current_repo: nil,
              current_org: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
          else
            raise Platform::Errors::Internal, "Somehow found a public key without a repo or user, ID = #{key.id}"
          end
        end
      end

      def self.async_user_and_repository(key)
        Promise.all([key.async_user, key.async_repository])
      end

      private

      def async_viewer_can_read_sensitive_fields
        if viewing_via_stafftools?
          Promise.resolve(true)
        else
          ::Platform::Objects::PublicKey.async_user_and_repository(@object).then do |user, repository|
            @context[:permission].async_integration_can_read_public_key?(@object).then do |integration_can_read_public_key|
              (integration_can_read_public_key && @context[:viewer] == user) || repository
            end
          end
        end
      end

      def viewing_via_stafftools?
        # re: context[:origin], allow staff via stafftools but not via staff-authorized apps
        @context[:viewer]&.site_admin? && !Platform.requires_scope?(@context[:origin])
      end
    end
  end
end
