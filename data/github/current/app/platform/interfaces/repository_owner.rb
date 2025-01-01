# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module RepositoryOwner
      include Platform::Interfaces::Base
      include Platform::Interfaces::FeatureFlaggable

      description "Represents an owner of a Repository."

      field :id, ID, description: "The Node ID of the RepositoryOwner object", method: :global_relay_id, null: false

      field :login, String, "The username used to login.", null: false, method: :login_for_api

      field :url, Scalars::URI, description: "The HTTP URL for the owner.", null: false

      field :resource_path, Scalars::URI, "The HTTP URL for the owner.", null: false

      database_id_field(visibility: :internal)

      field :avatar_url, Scalars::URI, description: "A URL pointing to the owner's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      field :repository, Objects::Repository, description: "Find Repository.", null: true do
        argument :name, String, "Name of Repository to find.", required: true
        argument :follow_renames, Boolean, "Follow repository renames. If disabled, a repository referenced by its old name will return an error.", default_value: true, required: false
      end

      def repository(**arguments)
        Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
          permission: @context[:permission],
          viewer: @context[:viewer],
          login: @object.display_login,
          name: arguments[:name],
          follow_repo_redirect: arguments[:follow_renames]
        )
      end

      field :viewer_can_administer, Boolean, visibility: :internal, description: "Owner of repo is adminable by the viewer.", null: false

      def viewer_can_administer
        @object.adminable_by?(@context[:viewer])
      end

      field :retired_namespaces, Connections.define(Platform::Objects::RetiredNamespace), visibility: :internal, description: "A list of retired namespaces for this owner", null: false, connection: true

      def retired_namespaces
        unless @context[:viewer].site_admin?
          raise Errors::Forbidden.new("#{@context[:viewer].login_for_api} does not have permission to retrieve retired namespaces.")
        end

        ::RetiredNamespace.for_owner(@object)
      end

      field :repositories, resolver: Resolvers::Repositories, connection: true do
        description "A list of repositories that the user owns."
        argument :is_archived, Boolean, "If non-null, filters repositories according to whether they are archived and not maintained", required: false
        argument :is_fork, Boolean, "If non-null, filters repositories according to whether they are forks of another repository", required: false
      end

      field :repositories_using_dependencies, [Objects::RepositoriesUsingDependency], visibility: :under_development, null: false do
        description "Get a list of this user or organization's repositories that use any of the " \
          "specified dependencies."
        argument :dependency_ids, [ID], "Repository IDs for dependencies to look up.",
          required: true
      end

      def repositories_using_dependencies(**inputs)
        dependency_promises = inputs[:dependency_ids].map do |gid|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id \
            [Objects::Repository], gid, @context
        end

        Promise.all(dependency_promises).then do |dependencies|
          owner_id = @object.id
          dependency_ids = dependencies.map(&:id)
          loader = ::Repository::RepositoriesUsingDependenciesLoader.new(owner_id: owner_id,
            dependency_ids: dependency_ids)

          loader.async_repos_using_dependencies.then do |list|
            ArrayWrapper.new(list)
          end
        end
      end

      field :template_repositories, resolver: Resolvers::TemplateRepositories,
        visibility: :under_development, connection: true do
          description "A list of template repositories relevant to this user or organization."
        end

      field :is_actions_eligible, Boolean, visibility: :internal, description: "Owner's eligibility to use Actions", null: false

      def is_actions_eligible
        @object.async_customer.then do
          Billing::ActionsPermission.new(@object).allowed?
        end
      end

      field :actions_status, Objects::ActionsStatus, visibility: :internal,
        null: true, description: "The image used to represent this repository in Open Graph data."

      def actions_status
        @object
      end

      field :issue_types_enabled, Boolean, visibility: :internal, description: "Whether or not issue types are enabled for this user.", null: false, method: :issue_types_enabled?

      field :is_usage_allowed, Boolean, visibility: :internal, description: "Returns whether or not an action can be run at this time", null: false do
        argument :public, Boolean, "Is usage for public use", required: true
      end

      def is_usage_allowed(**arguments)
        @object.async_budgets.then do
          @object.async_customer.then do
            Billing::ActionsPermission.new(@object).usage_allowed?(public: arguments[:public])
          end
        end
      end

      field :is_storage_allowed, Boolean, visibility: :internal, description: "Returns whether or not the given amount of bytes would go over storage limits", null: false do
        argument :public, Boolean, "Is storage for public use", required: true
      end

      def is_storage_allowed(**arguments)
        @object.async_budgets.then do
          @object.async_customer.then do
            Billing::ActionsPermission.new(@object).storage_allowed?(
              public: arguments[:public],
            )
          end
        end
      end

      field :is_spammy, Boolean, visibility: :internal, description: "Whether or not the user is spammy.", null: false, method: :spammy?
    end
  end
end
