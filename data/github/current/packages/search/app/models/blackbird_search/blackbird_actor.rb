# typed: strict
# frozen_string_literal: true

module BlackbirdSearch
  class BlackbirdActor
    sig { returns(T.nilable(T.any(User, Bot))) }
    attr_reader :actor

    sig { returns(T.nilable(UserSession)) }
    attr_reader :session

    sig { returns(String) }
    attr_reader :token_kind

    sig do
      params(
        actor: T.any(User, Bot),
        session: T.nilable(UserSession), # UserSession only applies for web actors, and is nil for API actors.
        request_user_ip: String,
        token_kind: String, # Expected to be one of ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_API or ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB.
      ).void
    end
    def initialize(actor:, session:, request_user_ip:, token_kind:)
      @actor = actor
      @session = session
      @request_user_ip = request_user_ip
      @token_kind = token_kind
      @cap_filter = T.let(cap_filter, T.nilable(T.any(ConditionalAccess::Api::Public::Filter, ConditionalAccess::Model::Filter)))
      @actor_resources = T.let(ActorResources.new(current_user: actor, cap_filter: @cap_filter), ActorResources)
    end

    sig { returns(::Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources) }
    def accessible_resources
      @accessible_resources ||= T.let(begin
        auth_actor = if @token_kind == ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
          ApiActor.new(actor: @actor, remote_ip: @request_user_ip)
        else
          WebActor.new(actor: @actor, session: T.must(@session), remote_ip: @request_user_ip)
        end

        ::Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources.new(
          accessible_private_repo_ids: auth_actor.accessible_private_repo_ids,
          accessible_owner_ids: auth_actor.accessible_owner_ids,
          authorized_organization_ids: auth_actor.authorized_organization_ids,
          protected_organization_ids: auth_actor.protected_organization_ids,
        )
      end, T.nilable(::Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources))
    end

    sig { returns(T::Boolean) }
    def compare_against_v1
      auth_actor = if @token_kind == ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
        ApiActor.new(actor: @actor, remote_ip: @request_user_ip)
      else
        WebActor.new(actor: @actor, session: T.must(@session), remote_ip: @request_user_ip)
      end

      v1_accessible_resources = auth_actor.accessible_resources

      mismatch = false
      if accessible_resources.accessible_private_repo_ids != v1_accessible_resources.accessible_private_repo_ids
        GitHub.logger.info("blackbird mismatch", "field" => "accessible_private_repo_ids", "v1_len" => accessible_resources.accessible_private_repo_ids.length, "v2_len" => v1_accessible_resources.accessible_private_repo_ids.length)
        mismatch = true
      end

      if accessible_resources.accessible_owner_ids.sort != v1_accessible_resources.accessible_owner_ids.sort
        GitHub.logger.info("blackbird mismatch", "field" => "accessible_owner_ids", "v1_len" => accessible_resources.accessible_owner_ids.length, "v2_len" => v1_accessible_resources.accessible_owner_ids.length)
        mismatch = true
      end

      if accessible_resources.authorized_organization_ids.sort != v1_accessible_resources.authorized_organization_ids.sort
        GitHub.logger.info("blackbird mismatch", "field" => "authorized_organization_ids", "v1_len" => accessible_resources.authorized_organization_ids.length, "v2_len" => v1_accessible_resources.authorized_organization_ids.length)
        mismatch = true
      end

      if accessible_resources.protected_organization_ids.sort != v1_accessible_resources.protected_organization_ids.sort
        GitHub.logger.info("blackbird mismatch", "field" => "protected_organization_ids", "v1_len" => accessible_resources.protected_organization_ids.length, "v2_len" => v1_accessible_resources.protected_organization_ids.length)
        mismatch = true
      end

      GitHub.dogstats.increment("blackbird_actor_compare", tags: ["token_kind:#{@token_kind}", "mismatch:#{mismatch}"])
      mismatch
    end

    private

    # Returns a unique, sorted list of private repository ids the actor is authorized to view.
    sig { returns(T.nilable(T::Array[Integer])) }
    def accessible_private_repo_ids
      @accessible_private_repo_ids ||= T.let(ActiveRecord::Base.connected_to(role: :reading) do
        return [] unless Api::AccessControl.scope?(@actor, "repo") if api_actor?

        repo_ids = T.unsafe(Repository.private_scope.active).
          batched_scope(:id, values: @actor.associated_repository_ids(resource: "contents"), batch_size: 2_000). # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          pluck(:id)

        if @actor_resources.accessible_business_ids.any?
          repo_ids.concat(InternalRepository.where(business_id: @actor_resources.accessible_business_ids).joins(:repository).where(repositories: { active: true }).pluck(:repository_id))
        end

        sorted_accessible_repo_ids = (repo_ids - @actor_resources.protected_repo_ids).uniq.sort

        if api_actor?
          ProgrammaticActor::RepositoryFilter.perform(actor: @actor, repository_ids: sorted_accessible_repo_ids, resource: "contents")
        else
          sorted_accessible_repo_ids
        end
      end, T.nilable(T::Array[Integer]))
    end

    # Returns a unique, sorted list of organization ids the actor is authorized to access and has valid CAP.
    sig { returns(T::Array[Integer]) }
    def authorized_organization_ids
      @authorized_organization_ids ||= T.let(ActiveRecord::Base.connected_to(role: :reading) do
        if api_actor? && @actor.can_have_granular_permissions?
          # For fine-grained actors like GitHub Apps, return the target if it has been "installed".
          ability_delegate = @actor.ability_delegate
          if ability_delegate.try(:target).instance_of?(Organization)
            [ability_delegate.target_id] - protected_organization_ids
          else
            []
          end
        else
          @actor_resources.authorized_organization_ids
        end
      end, T.nilable(T::Array[Integer]))
    end

    sig { returns(T::Array[Integer]) }
    def outside_collaborator_owner_ids
      @outside_collaborator_owner_ids ||= T.let(ActiveRecord::Base.connected_to(role: :reading) do
        if api_actor? && @actor.can_have_granular_permissions?
          # Fine-grained actors cannot be outside collaborators.
          []
        elsif api_actor?
          # Find all direct repos the user has access to.
          repository_ids = @actor.associated_repository_ids(including: [:direct])

          # Ensure the repositories provided are accessible within the context of the API.
          if ProgrammaticActor::RepositoryFilter.applicable?(@actor)
            repository_ids = ProgrammaticActor::RepositoryFilter.perform(
              actor: @actor,
              repository_ids: repository_ids,
              resource: "contents"
             )
          end

          filter = User::OrganizationFilter.new(@actor)

          repository_ids.in_groups_of(1_000, false).map do |repo_ids|
            Repository.
              active.
              where(id: repo_ids).
              where.not(owner_id: filter.scoped_ids).
              distinct.
              pluck(:owner_id)
          end.flatten.uniq
        else
          @actor_resources.outside_collaborator_owner_ids
        end
      end, T.nilable(T::Array[Integer]))
    end

    # Returns a unique list of all organization ids including the actor's id and outside collaborator owner ids.
    sig { returns(T::Array[Integer]) }
    def accessible_owner_ids
      @accessible_owner_ids ||= T.let([T.must(@actor.id), *authorized_organization_ids, *outside_collaborator_owner_ids], T.nilable(T::Array[Integer]))
    end

    # Returns a list of organization ids the actor is a member of but does not have valid CAP.
    sig { returns(T::Array[Integer]) }
    def protected_organization_ids
      @protected_organization_ids ||= T.let(@actor_resources.protected_organization_ids, T.nilable(T::Array[Integer]))
    end

    sig { returns(T::Boolean) }
    def api_actor?
      @token_kind == ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    sig { returns(T.nilable(T.any(User, Bot))) }
    def current_user
      @actor
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    sig { returns(T::Boolean) }
    def logged_in?
      true
    end

    # for compatibility with ConditionalAccess::Api::Public::Filter
    sig { returns(String) }
    def ip_for_allowed_check
      @request_user_ip
    end

    sig { returns(T.any(ConditionalAccess::Api::Public::Filter, ConditionalAccess::Model::Filter)) }
    def cap_filter
      if api_actor?
        ConditionalAccess::Api::Public::Filter.new(self)
      else
        ConditionalAccess::Model::Filter.new(self,
          web_session: @session,
          actor: @actor,
          remote_ip: @request_user_ip,
          location: :internal_api)
      end
    end
  end
end
