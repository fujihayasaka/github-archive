# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryProjectTerm < Platform::Objects::Base
      description "Known project term and value extracted from a search shortcut query string"
      scopeless_tokens_as_minimum
      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      implements Interfaces::SearchShortcutQueryBasicTerm
      implements Interfaces::SearchShortcutQueryParsedTerm

      OWNER_REPO_NUMBER_REGEX = /\A([^\/]+)\/([^\/]+)\/(\d*)\Z/
      OWNER_NUMBER_REGEX = /\A([^\/]+)\/([^\/]+)\Z/

      field :project, Objects::Project, "The project referenced in this term", null: true, deprecated: Helpers::ProjectDeprecation::Notice

      def project
        promise =
          if match = OWNER_REPO_NUMBER_REGEX.match(object[:value])
            async_project_by_owner_and_repo(match.captures[0], match.captures[1], match.captures[2])
          elsif match = OWNER_NUMBER_REGEX.match(object[:value])
            async_project_by_owner(*match.captures[0], match.captures[1])
          else
            Promise.resolve(nil)
          end

        promise&.then do |project|
          next unless project
          type_name = Helpers::NodeIdentification.type_name_from_object(project)
          context[:permission].typed_can_see?(type_name, project).then do |can_read|
            next unless can_read
            project
          end
        end
      end

      private

      def async_project_by_owner_and_repo(owner_login, repo_name, project_number)
        Loaders::RepositoryByNwo.load("#{owner_login}/#{repo_name}").then do |repo|
          next unless repo
          repo.async_projects_enabled?.then do |projects_enabled|
            next unless projects_enabled
            Loaders::ProjectByNumber.load(repo, project_number.to_i)
          end
        end
      end

      def async_project_by_owner(owner_login, project_number)
        Loaders::ActiveRecord.load(::Organization, owner_login, column: :login).then do |owner|
          next unless owner
          owner.async_projects_enabled?.then do |projects_enabled|
            next unless projects_enabled

            Loaders::ProjectByNumber.load(owner, project_number.to_i)
          end
        end
      end
    end
  end
end
