# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Repositories
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  extend T::Helpers

  requires_ancestor { Kernel }

  included do
    field :repository_owner, Interfaces::RepositoryOwner, description: "Lookup a repository owner (ie. either a User or an Organization) by login.", null: true do
      argument :login, String, "The username to lookup the owner by.", required: true
    end

    def repository_owner(**arguments)
      if arguments.key?(:login) && arguments[:login].ends_with?(Bot::LOGIN_SUFFIX)
        raise Platform::Errors::NotFound, "Could not resolve to a User or Organization with the username '#{arguments[:login]}'."
      end

      Loaders::ActiveRecord.load(::User, arguments[:login], column: :login, case_sensitive: false).then do |owner|
        @context[:permission].typed_can_see?(owner.class.name, owner).then do |owner_readable|
          if owner && owner_readable && !owner.hide_from_user?(@context[:viewer])
            owner
          end
        end
      end
    end

    field :public_repositories, Connections::Repository, visibility: :internal, description: <<~DESCRIPTION, null: false, connection: true do
        Look up multiple public repositories by their owners and names, as well as by database ID.
      DESCRIPTION

      argument :names_with_owners, [String], "A list of repository owners and names, e.g., github/linguist.", required: false
      argument :database_ids, [Integer], "A list of repository database IDs.", required: false
    end

    def public_repositories(**arguments)
      conditions = []

      if arguments[:database_ids].present?
        conditions << ::Repository.where(id: arguments[:database_ids])
      end

      if arguments[:names_with_owners].present?
        arguments[:names_with_owners].each do |nwo|
          owner, name = nwo.split("/")
          conditions << ::Repository.where(owner_login: owner, name: name)
        end
      end

      repositories = if FeatureFlag.vexi.enabled?(:repos_gql_public_active, default: false)
        ::Repository.public_scope.active
      else
        ::Repository.public_scope
      end
      repositories = repositories.and(conditions.reduce { |a, b| a.or(b) }) if conditions.present?
      repositories.filter_spam_and_disabled_for(@context[:viewer])
    end

    field :staff_accessed_repository, Objects::StaffAccessedRepository, null: true,
      description: "A way for GitHub staff members to see a narrow subset of data about any repository in the system",
      visibility: :internal do
        argument :owner, String, "The login field of a user or organization", required: true
        argument :name, String, "The name of the repository", required: true
      end

    # This field does _not_ use `Platform::Security::RepositoryAccess` because it returns a
    # `StaffAccessedRepository`, which only allows staff and only exposes a few repository fields
    def staff_accessed_repository(name:, owner:)
      Loaders::ActiveRecord.load(::User, owner, column: :login, case_sensitive: false).then do |owner|
        # disabling linter since this is only visible internally to staff
        could_not_resolve_owner = "Could not resolve to a User with the username '#{owner}'." # rubocop:disable GitHub/DoNotAllowLogin
        could_not_resolve_repo  = "Could not resolve to a Repository."
        if owner.blank?
          raise Platform::Errors::NotFound, could_not_resolve_owner
        end
        @context[:permission].typed_can_see?("User", owner).then do |owner_readable|
          if !owner_readable
            raise Platform::Errors::NotFound, could_not_resolve_owner
          end

          repo = owner.find_repo_by_name(name)

          if repo.blank?
            raise Platform::Errors::NotFound, could_not_resolve_repo
          end

          @context[:permission].typed_can_see?("Repository", repo).then do |repo_readable|
            repo_readable ? repo : raise(Platform::Errors::NotFound, could_not_resolve_repo)
          end
        end
      end
    end

    field :repository, Objects::Repository, description: "Lookup a given repository by the owner and repository name.", null: true do
      argument :owner, String, "The login field of a user or organization", required: true
      argument :name, String, "The name of the repository", required: true
      argument :follow_renames, Boolean, "Follow repository renames. If disabled, a repository referenced by its old name will return an error.", default_value: true, required: false
    end

    def repository(**arguments)
      Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
        permission: @context[:permission],
        viewer: @context[:viewer],
        login: arguments[:owner],
        name: arguments[:name],
        follow_repo_redirect: arguments[:follow_renames],
      )
    end
  end
end
