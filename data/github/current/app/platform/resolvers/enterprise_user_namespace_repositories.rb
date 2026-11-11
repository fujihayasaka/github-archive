# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseUserNamespaceRepositories < Resolvers::Base
      type Connections.define(Objects::UserNamespaceRepository), null: false
      argument :query, String, "The search string to look for.", required: false

      argument :order_by, Inputs::RepositoryOrder,
        "Ordering options for repositories returned from the connection.",
        required: false, default_value: { field: "name", direction: "ASC" }

      argument :repo_status, Enums::UserNamespaceRepositoriesFilter,
        Enums::UserNamespaceRepositoriesFilter.description,
        required: false

      def resolve(query: nil, order_by: nil, repo_status: nil)
        ensure_business_can_use_api!(object)

        unless object.show_user_namespace_repositories?
          raise Platform::Errors::Forbidden.new("User namespace repositories are not available for this enterprise.")
        end

        unless object.adminable_by?(context[:viewer]) || SecurityProduct::Permissions::BusinessAuthz.new(object, actor: context[:viewer]).can_unlock_user_owned_repositories?
          raise Platform::Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to view user namespace repositories.")
        end

        repos = object.user_namespace_repositories(
          query: query,
          status: repo_status,
          repository_ids: repo_status == :unlocked ? unlocked_repository_ids : [],
          sort_direction: order_by&.dig(:direction),
          sort_field: order_by&.dig(:field),
        )

        ArrayWrapper.new(repos)
      end

      private

      def unlocked_repository_ids
        return [] unless context[:viewer].is_a?(User) && object.can_user_unlock_user_namespace_repos?(context[:viewer])

        RepositoryUnlock.active_for_user(context[:viewer]).pluck(:repository_id)
      end
    end
  end
end
