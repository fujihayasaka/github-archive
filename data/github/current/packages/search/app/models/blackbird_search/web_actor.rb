# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class WebActor
    attr_reader :actor, :session

    sig { params(actor: User, session: UserSession, remote_ip: T.nilable(String)).void }
    def initialize(actor:, session:, remote_ip: nil)
      @actor = actor
      @session = session
      @remote_ip = remote_ip
      @actor_resources = ActorResources.new(current_user: actor, cap_filter: cap_filter)
    end

    # Public: List of all private repositories that the access_token's user
    # session has read access to.
    #
    # Returns a sorted set of repository ids as an Array of Integer.
    def accessible_repository_ids
      return @accessible_repository_ids if defined? @accessible_repository_ids

      ActiveRecord::Base.connected_to(role: :reading) do
        repo_ids = T.unsafe(Repository.private_scope.active).
          batched_scope(:id, values: @actor.associated_repository_ids, batch_size: 2_000). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          pluck(:id)

        if @actor_resources.accessible_business_ids.any?
          repo_ids.concat(InternalRepository.where(business_id: @actor_resources.accessible_business_ids).joins(:repository).where(repositories: { active: true }).pluck(:repository_id))
        end

        @accessible_repository_ids = (repo_ids - @actor_resources.protected_repo_ids).uniq.sort
      end
    end

    alias :accessible_private_repo_ids :accessible_repository_ids

    def accessible_owner_ids
      @accessible_owner_ids ||= [@actor.id, *authorized_organization_ids, *outside_collaborator_owner_ids].uniq
    end

    def outside_collaborator_owner_ids
      @actor_resources.outside_collaborator_owner_ids
    end

    def authorized_organization_ids
      @actor_resources.authorized_organization_ids
    end

    def protected_organization_ids
      @actor_resources.protected_organization_ids
    end

    def cap_filter
      @conditional_access_filter ||= begin
        ConditionalAccess::Model::Filter.new(self,
          web_session: @session,
          actor: @actor,
          remote_ip: @remote_ip,
          location: :internal_api)
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
