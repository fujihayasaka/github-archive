# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class ApiActor
    include Scientist
    attr_reader :actor

    sig { params(actor: T.any(User, Bot), remote_ip: String).void }
    def initialize(actor:, remote_ip:)
      @actor = actor
      @remote_ip = remote_ip
      @actor_resources = ActorResources.new(current_user: actor, cap_filter: cap_filter)
    end

    # Public: List of all private repositories that a user or bot has read access to according to the authentication type and the allowed scopes.
    #
    # Returns Array of Integer.
    def accessible_repository_ids
      return @accessible_repository_ids if defined? @accessible_repository_ids
      # Without the repo scope, accessible_repository_ids is going to be empty
      return [] unless Api::AccessControl.scope?(@actor, "repo")

      ActiveRecord::Base.connected_to(role: :reading) do
        repo_ids = T.unsafe(Repository.private_scope.active).
          batched_scope(:id, values: @actor.associated_repository_ids(resource: "contents"), batch_size: 2_000). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          pluck(:id)

        if @actor_resources.accessible_business_ids.any?
          repo_ids.concat(Repositories.domain.internal_repo_ids_by_business_ids(business_ids: @actor_resources.accessible_business_ids, active_only: true))
        end

        @accessible_repository_ids =
          ProgrammaticActor::RepositoryFilter.perform(
            actor: @actor,
            repository_ids: (repo_ids - @actor_resources.protected_repo_ids).uniq,
            resource: "contents",
          ).sort
      end
    end

    alias :accessible_private_repo_ids :accessible_repository_ids

    def outside_collaborator_owner_ids
      return @outside_collaborator_owner_ids if defined?(@outside_collaborator_owner_ids)

      @outside_collaborator_owner_ids = []

      ActiveRecord::Base.connected_to(role: :reading) do
        # Fine-grained actors cannot be outside collaborators
        if @actor.can_have_granular_permissions?
          return @outside_collaborator_owner_ids
        end

        # Find all direct repos the user has access to.
        repository_ids = @actor.associated_repository_ids(including: [:direct])

        # Ensure the repositories provided are accessible within the context of
        # the API.
        if ProgrammaticActor::RepositoryFilter.applicable?(@actor)
          repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            actor: @actor,
            repository_ids: repository_ids,
            resource: "contents"
           )
        end

        filter = User::OrganizationFilter.new(@actor)

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
      return @authorized_organization_ids if defined?(@authorized_organization_ids)

      @authorized_organization_ids = []

      unless @actor.can_have_granular_permissions?
        @authorized_organization_ids = @actor_resources.authorized_organization_ids
        return @authorized_organization_ids
      end

      # For fine-grained actors like GitHub Apps, return the target if it has
      # been "installed".
      ability_delegate = @actor.ability_delegate

      @authorized_organization_ids =
        if ability_delegate.try(:target).instance_of?(Organization)
          [ability_delegate.target_id]
        else
          []
        end

      @authorized_organization_ids -= protected_organization_ids
    end

    def accessible_owner_ids
      @accessible_owner_ids ||= [@actor.id, *authorized_organization_ids, *outside_collaborator_owner_ids].uniq
    end

    def protected_organization_ids
      @actor_resources.protected_organization_ids
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    def current_user
      @actor
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

    def accessible_resources
      return @accessible_resources if defined?(@accessible_resources)

      @accessible_resources = ::Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources.new(
        accessible_private_repo_ids: accessible_private_repo_ids,
        accessible_owner_ids: accessible_owner_ids,
        authorized_organization_ids: authorized_organization_ids,
        protected_organization_ids: protected_organization_ids,
      )
    end
  end
end
