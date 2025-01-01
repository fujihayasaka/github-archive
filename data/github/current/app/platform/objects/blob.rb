# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Blob < Platform::Objects::Base
      description "Represents a Git blob."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, blob)
        repo = blob.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_blob, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_git_object(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::GitObject

      implements_node templates: [[:rb, :repo_id, :oid]], as: "B", ready_date: Platform::Helpers::GlobalId::COHORT_4, uses_database_id: false do |blob|
        {
          prefix: :rb,
          repo_id: blob.repository.id,
          oid: blob.oid
        }
      end

      field :byte_size, Integer, "Byte size of Blob object", method: :size, null: false

      field :is_binary, Boolean, "Indicates whether the Blob is binary or text. Returns null if unable to determine the encoding.", method: :binary?, null: true

      field :is_truncated, Boolean, "Indicates whether the contents is truncated", method: :truncated?, null: false

      field :text, String, description: "UTF8 text data or null if the Blob is binary", null: true

      def text
        if @object.binary?
          nil
        else
          @object.data
        end
      end

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]
        unless prefix == :rb
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        repo_id = parsed_id.parts[:repo_id]
        oid = parsed_id.parts[:oid]

        Loaders::ActiveRecord.load(::Repository, repo_id, security_violation_behaviour: :nil).then do |repo|
          if repo
            Loaders::GitObject.load(repo, oid)
          end
        end
      end

      def self.load_from_global_id(id)
        Interfaces::GitObject.load_from_global_id(id)
      end
    end
  end
end
