# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserList < Platform::Objects::Base
      description "A user-curated list of repositories"

      implements_node templates: [[:ul, :user_id, :user_list_id]], as: "UL", ready_date: "1970-01-01" do |list|
        {
          prefix: :ul,
          user_id: list.user_id,
          user_list_id: list.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user_list)
        user_list.async_user.then do
          # user is used in the target_for_conditional_access so it is loaded here
          public_resource = Platform::PublicResource.new(resource: user_list)
          permission.access_allowed?(
            :read_user_public,
            resource: public_resource,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if !object.private?
        return false if permission.viewer.nil?

        object.async_user.then do |user|
          permission.viewer == user
        end
      end

      scopeless_tokens_as_minimum

      field :user, Objects::User, "The user to which this list belongs", null: false

      field :name, String, "The name of this list", null: false

      field :slug, String, "The slug of this list", null: false

      field :description, String, "The description of this list", null: true

      field :is_private, Boolean, "Whether or not this list is private", null: false, method: :private?

      field :last_added_at, Scalars::DateTime, "The date and time at which this list was created or last had items added to it", null: false

      created_at_field

      updated_at_field

      field :items, Connections.define(Unions::UserListItems), "The items associated with this list", null: false

      # items could some day return multiple types. For now
      # it's limited to repositories
      def items
        object.async_items.then do |items|
          repo_ids = items.map(&:repository_id)

          Loaders::ActiveRecord.load_all(::Repository, repo_ids, security_violation_behaviour: :nil).then do |repositories|
            ArrayWrapper.new(repositories.compact)
          end
        end
      end
    end
  end
end
