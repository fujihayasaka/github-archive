# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class WebActor
    extend T::Sig

    sig { returns(GitHub::Authentication::SignedAuthToken) }
    attr_reader :access_token

    sig { params(access_token: GitHub::Authentication::SignedAuthToken, remote_ip: T.nilable(String)).void }
    def initialize(access_token:, remote_ip: nil)
      T.assert_type!(access_token, GitHub::Authentication::SignedAuthToken)
      @access_token = access_token
      @remote_ip = remote_ip
      @actor_resources = ActorResources.new(current_user: current_user, cap_filter: cap_filter)
    end

    # Public: List of all private repositories that the access_token's user
    # session has read access to.
    #
    # Returns Array of Integer.
    def accessible_repository_ids
      return @accessible_repository_ids if defined? @accessible_repository_ids

      ActiveRecord::Base.connected_to(role: :reading) do
        repo_ids = T.unsafe(Repository.private_scope.active).
          batched_scope(:id, values: current_user.associated_repository_ids, batch_size: 2_000). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          pluck(:id)

        if @actor_resources.accessible_business_ids.any?
          repo_ids.concat(InternalRepository.where(business_id: @actor_resources.accessible_business_ids).joins(:repository).where(repositories: { active: true }).pluck(:repository_id))
        end

        @accessible_repository_ids = (repo_ids - @actor_resources.protected_repo_ids).uniq
      end
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

    def current_user
      access_token.user
    end

    def cap_filter
      @conditional_access_filter ||= begin
        ConditionalAccess::Model::Filter.new(self,
          web_session: access_token.session,
          actor: current_user,
          remote_ip: @remote_ip,
          location: :internal_api)
      end
    end
  end
end
