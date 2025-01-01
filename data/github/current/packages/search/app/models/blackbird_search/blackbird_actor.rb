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
        auth_actor = if api_actor?
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

    private

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
        ConditionalAccess::Model::Filter.new(self, # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
          web_session: @session,
          actor: @actor,
          remote_ip: @request_user_ip,
          location: :internal_api)
      end
    end
  end
end
