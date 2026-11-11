# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestCreationCapConfig < Platform::Objects::Base
      docs_category :pulls

      description "Users who are exempt from the pull request creation cap on a repository."

      def self.async_api_can_access?(permission, object)
        repository = object[:repository]
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(
            :edit_repo,
            resource: repository,
            repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object[:repository])
      end

      minimum_accepted_scopes ["public_repo"]

      field :bypassed_users, Connections::User,
        description: "Users who are exempt from the pull request creation cap.",
        null: false,
        connection: true

      def bypassed_users
        repository = @object[:repository]
        config = PullRequestCreationConfig.new(repository)
        user_ids = config.pull_request_creation_cap_bypass_user_ids
        return ArrayWrapper.new([]) if user_ids.empty?

        ArrayWrapper.new(::User.where(id: user_ids).to_a)
      end
    end
  end
end
