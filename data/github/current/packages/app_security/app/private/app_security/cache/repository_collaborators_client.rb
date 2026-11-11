# typed: strict
# frozen_string_literal: true

module AppSecurity
  module Cache
    class RepositoryCollaboratorsClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = :repos_list_collaborators
      FALLBACK       = T.let(Set[-1].freeze, T::Set[Integer])
      NO_ACTION      = "no-action"
      NO_AFFILIATION = "no-affiliation"

      SourceKeyType = type_member { { fixed: [Repository, User, String, String] } }
      SourceValueType = type_member { { fixed: T::Set[Integer] } }

      sig do
        params(
          repo: Repository,
          viewer: User,
          action: T.nilable(Symbol),
          affiliation: T.nilable(String)
        ).void
      end
      def initialize(repo, viewer:, action:, affiliation:)
        @repo = T.let(repo, Repository)
        @viewer = viewer
        @action = T.let((action || NO_ACTION).to_s, String)
        @affiliation = T.let(affiliation || NO_AFFILIATION, String)
      end

      sig { override.params(source_key: SourceKeyType).returns(String) }
      def cache_key_id(source_key)
        repo, viewer, action, affiliation = source_key

        parts = ["repo:#{repo.id}"]

        if viewer_cache_key_applicable?(viewer, action, affiliation)
          parts << viewer_cache_key(viewer)
        end

        parts.concat([
          action,
          affiliation
        ])

        parts.join(":")
      end

      sig { override.returns(Symbol) }
      def cache_key_name
        CACHE_KEY_NAME
      end

      sig { override.returns(T::Boolean) }
      def enabled?
        @repo.feature_flag_enabled?(:repo_list_collaborators_cache_enabled, default: false)
      end

      sig { override.returns(SourceValueType) }
      def fallback
        FALLBACK
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        GitHub::RemoteCache::NumericSetSerializer
      end

      sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
      def staleness_observer
        GitHub::RemoteCache::PrimitiveValueStalenessObserver
      end

      sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
      def rollout_mode
        if @repo.feature_flag_enabled?(:repo_list_collaborators_cache_shadow, default: true)
          GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
        else
          GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
        end
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        [[@repo, @viewer, @action, @affiliation]]
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        percentage_of_actors_value = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:repo_list_collaborators_redis_cache_ttl) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        (percentage_of_actors_value * 100).to_i # 0.5% of actors -> 50 seconds of TTL
      end

      private

      sig { override.returns(GitHub::RemoteCache::Client) }
      def cache_client
        AppSecurity::Cache.client
      end

      # Private: Determines whether to include the viewer in the cache key.
      # This is only necessary for certain combinations of action and
      # affiliation.
      #
      # Returns a Boolean.
      sig { params(viewer: T.untyped, action: String, affiliation: String).returns(T::Boolean) }
      def viewer_cache_key_applicable?(viewer, action, affiliation)
        case affiliation
        when NO_AFFILIATION
          true
        when "direct"
          action != NO_ACTION
        else
          false
        end
      end

      sig { params(viewer: T.untyped).returns(String) }
      def viewer_cache_key(viewer)
        actor = viewer.respond_to?(:ability_delegate) ? viewer.ability_delegate : viewer

        key =
          case actor
          when User
            if (oauth_access = actor.try(:oauth_access))
              viewer_cache_key(oauth_access.authorization)
            elsif (programmatic_access = actor.try(:programmatic_access))
              viewer_cache_key(programmatic_access)
            else
              "user:#{actor.id}"
            end
          else
            "#{actor.class.name}:#{actor.id}"
          end

        key.underscore
      end
    end
  end
end
