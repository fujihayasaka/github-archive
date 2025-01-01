# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class ApiActor
    extend T::Sig

    sig { returns(GitHub::Authentication::Result) }
    attr_reader :auth_result

    sig { params(auth_result: GitHub::Authentication::Result, remote_ip: String).void }
    def initialize(auth_result:, remote_ip:)
      T.assert_type!(auth_result, GitHub::Authentication::Result)
      @auth_result = auth_result
      @remote_ip = remote_ip
      @actor_resources = ActorResources.new(current_user: current_user, cap_filter: cap_filter)
    end

    # Public: List of all private repositories that the access_token's user
    # session has read access to.
    #
    # Returns Array of Integer.
    def accessible_repository_ids
      return @accessible_repository_ids if defined? @accessible_repository_ids
      # Without the repo scope, accessible_repository_ids is going to be empty
      return [] unless Api::AccessControl.scope?(current_user, "repo")

      ActiveRecord::Base.connected_to(role: :reading) do
        repo_ids = T.unsafe(Repository.private_scope.active).
          batched_scope(:id, values: current_user.associated_repository_ids(resource: "contents"), batch_size: 2_000). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          pluck(:id)

        if @actor_resources.accessible_business_ids.any?
          repo_ids.concat(InternalRepository.where(business_id: @actor_resources.accessible_business_ids).joins(:repository).where(repositories: { active: true }).pluck(:repository_id))
        end

        @accessible_repository_ids =
          ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            repository_ids: (repo_ids - @actor_resources.protected_repo_ids).uniq,
            resource: "contents",
          )
      end
    end

    def outside_collaborator_owner_ids
      return @outside_collaborator_owner_ids if defined?(@outside_collaborator_owner_ids)

      @outside_collaborator_owner_ids = []

      ActiveRecord::Base.connected_to(role: :reading) do
        # Fine-grained actors cannot be outside collaborators
        if current_user.can_have_granular_permissions?
          return @outside_collaborator_owner_ids
        end

        # Find all direct repos the user has access to.
        repository_ids = current_user.associated_repository_ids(including: [:direct])

        # Ensure the repositories provided are accessible within the context of
        # the API.
        if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
          repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: current_user,
            repository_ids: repository_ids,
            resource: "contents"
           )
        end

        filter = User::OrganizationFilter.new(current_user)

        repository_ids.in_groups_of(1_000, false) do |repo_ids|
          @outside_collaborator_owner_ids << Repository.
            active.
            where(id: repo_ids).
            where.not(owner_id: filter.scoped_ids).
            distinct.
            pluck(:owner_id)
        end

        @outside_collaborator_owner_ids = @outside_collaborator_owner_ids.flatten.uniq
      end
    end

    def authorized_organization_ids
      unless current_user.can_have_granular_permissions?
        return @actor_resources.authorized_organization_ids
      end

      # For fine-grained actors like GitHub Apps, return the target if it has
      # been "installed".
      ability_delegate = current_user.ability_delegate

      @authorized_organization_ids =
        if ability_delegate.try(:target).instance_of?(Organization)
          [ability_delegate.target_id]
        else
          []
        end

      @authorized_organization_ids -= protected_organization_ids
    end

    def protected_organization_ids
      @actor_resources.protected_organization_ids
    end

    def current_user
      auth_result.user
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    def logged_in?
      true
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    def ip_for_allowed_check
      @remote_ip
    end

    def cap_filter
      @conditional_access_filter ||= begin
        ConditionalAccess::Api::Public::Filter.new(self)
      end
    end

  end
end
